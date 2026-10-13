import test from 'node:test';import assert from 'node:assert/strict';import {PGlite} from '@electric-sql/pglite';import {randomUUID as key} from 'node:crypto';import {setupBusinessDB,actor,rpc,fixtureBusiness,testActors,point,destination} from './helpers/business-db.js';
test('phase 2 : inscription, autorisations, devis, stock, idempotence, courses et statuts',async()=>{
 const pg=new PGlite();const db={query:(sql,values)=>values?pg.query(sql,values):pg.exec(sql).then(results=>results.at(-1))};
 try{await setupBusinessDB(db);const f=await fixtureBusiness(db);
 await actor(db,testActors.client);const quote=await rpc(db,'quote',{category:'Taxi',start:point,end:destination});assert.ok(quote.fare_fcfa>500);
 const rideInput={request_id:key(),vehicle_id:f.vehicle.id,quote_id:quote.quote_id};const ride=await rpc(db,'reserve_ride',rideInput);assert.equal(ride.payload.tarif,quote.fare_fcfa);assert.equal((await rpc(db,'reserve_ride',rideInput)).id,ride.id);
 await assert.rejects(rpc(db,'reserve_ride',{...rideInput,request_id:key(),fare:1}),/Champs inconnus/);
 await assert.rejects(rpc(db,'transition',{request_id:key(),id:ride.id,next:'Acceptée',revision:ride.revision}),/Chauffeur assigné/);
 await actor(db,testActors.other);await assert.rejects(rpc(db,'get',{id:ride.id}),/Accès refusé/);assert.deepEqual(await rpc(db,'history',{kind:'courses'}),[]);
 await actor(db,testActors.driver);let current=ride;for(const next of ['Acceptée','Chauffeur en route','Course en cours','Terminée'])current=await rpc(db,'transition',{request_id:key(),id:ride.id,next,revision:current.revision});assert.equal(current.statut,'Terminée');
 await actor(db,testActors.client);const orderInput={request_id:key(),shop_id:f.shop.id,items:[{product_id:f.product.id,quantity:2}],mode:'retrait'};const order=await rpc(db,'create_order',orderInput);assert.equal(order.payload.total,1000);assert.equal((await rpc(db,'create_order',orderInput)).id,order.id);
 await assert.rejects(rpc(db,'create_order',{...orderInput,request_id:key(),items:[{product_id:f.product.id,quantity:1}]}),/stock insuffisant/);
 const cancelInput={request_id:key(),id:order.id,next:'Annulée',revision:order.revision};await rpc(db,'transition',cancelInput);await rpc(db,'transition',cancelInput);
 await actor(db,testActors.merchant);assert.equal((await rpc(db,'get',{id:f.product.id})).payload.stock,2);
 await actor(db,testActors.client);await assert.rejects(rpc(db,'create_order',{...orderInput,request_id:key(),total:1}),/Champs inconnus/);
 const request=await rpc(db,'request_service',{request_id:key(),service_id:f.service.id,need:'TEST réparation de fuite',address:'TEST adresse Koki',date:'2099-10-08'});assert.equal(request.statut,'Demande envoyée');
 await actor(db,testActors.merchant);await assert.rejects(rpc(db,'transition',{request_id:key(),id:request.id,next:'Acceptée',revision:request.revision}),/Accès refusé/);
 await actor(db,testActors.provider);const proposed=await rpc(db,'submit_service_quote',{request_id:key(),id:request.id,revision:request.revision,amount_fcfa:2500,description:'TEST réparation validée'});await actor(db,testActors.client);await assert.rejects(rpc(db,'accept_service_quote',{request_id:key(),id:request.id,revision:proposed.revision,amount_fcfa:1}),/Champs inconnus/);const acceptedService=await rpc(db,'accept_service_quote',{request_id:key(),id:request.id,revision:proposed.revision});assert.equal(acceptedService.payload.quote_fcfa,2500);await actor(db,testActors.provider);await rpc(db,'transition',{request_id:key(),id:request.id,next:'Prestataire en route',revision:acceptedService.revision});
 await actor(db,testActors.admin);await assert.rejects(rpc(db,'set_rate',{request_id:key(),category:'Taxi',base_fcfa:1,per_km_fcfa:1,active:true}),/MFA/);
 await actor(db,testActors.editor,'aal2');await assert.rejects(rpc(db,'admin_review',{request_id:key(),id:f.driver.id,decision:'approve'}),/MFA/);
 await actor(db,testActors.client);await assert.rejects(db.query("update public.koki_records set statut='Livrée' where id=$1",[order.id]),/permission denied/);
 await actor(db,null,'aal1','anon');const catalog=await rpc(db,'catalog');assert.ok(catalog.some(x=>x.id===f.product.id));assert.ok(!JSON.stringify(catalog).includes('position'));await assert.rejects(rpc(db,'history',{kind:'courses'}),/connecté/);
 }finally{await pg.close();}
});
