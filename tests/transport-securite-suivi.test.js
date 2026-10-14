// Transport : code de départ, expiration des demandes, suivi en direct, note, signalement, tableau du chauffeur.
import test from 'node:test';import assert from 'node:assert/strict';import {randomUUID as key} from 'node:crypto';
import {setupBusinessDB,actor,rpc,testActors as A,point,destination,fixtureBusiness} from './helpers/business-db.js';
async function base(){
 if(process.env.KOKI_DB_ADAPTER){const {psqlDB}=await import(process.env.KOKI_DB_ADAPTER);return psqlDB(process.env.KOKI_DB_NAME);}
 const {PGlite}=await import('@electric-sql/pglite');const pg=new PGlite();return {query:(q,v)=>v?pg.query(q,v):pg.exec(q).then(x=>x.at(-1)),close:()=>pg.close()};
}
async function reserver(db,f){await actor(db,A.client);const q=await rpc(db,'quote',{category:'Taxi',start:point,end:destination});return rpc(db,'reserve_ride',{request_id:key(),vehicle_id:f.vehicle.id,quote_id:q.quote_id});}
async function avancer(db,ride,next){await actor(db,A.driver);const r=await rpc(db,'get',{id:ride.id});return rpc(db,'transition',{request_id:key(),id:ride.id,next,revision:r.revision});}
test('course : code de départ réservé au client, saisi par le chauffeur, suivi, note et signalement',async()=>{
 const db=await base();
 try{
  await setupBusinessDB(db);const f=await fixtureBusiness(db);
  const ride=await reserver(db,f);assert.equal(ride.statut,'En attente');
  assert.equal((await rpc(db,'ride_code',{id:ride.id})).code,null,'pas de code avant acceptation');
  await avancer(db,ride,'Acceptée');
  await actor(db,A.client);const {code}=await rpc(db,'ride_code',{id:ride.id});assert.match(code,/^[0-9]{4}$/);
  await actor(db,A.driver);await assert.rejects(rpc(db,'ride_code',{id:ride.id}),/réservé au client/,'le chauffeur ne voit pas le code');
  await actor(db,A.other);await assert.rejects(rpc(db,'ride_tracking',{id:ride.id}),/réservé au client/);
  await actor(db,A.client);const t=await rpc(db,'ride_tracking',{id:ride.id});assert.equal(t.statut,'Acceptée');assert.ok(t.position&&Number.isFinite(t.position.latitude),'position du chauffeur');
  await avancer(db,ride,'Chauffeur en route');
  await assert.rejects(avancer(db,ride,'Course en cours'),/Code de départ requis/,'transition directe refusée');
  await actor(db,A.driver);let r=await rpc(db,'get',{id:ride.id});
  const faux=code==='0000'?'1111':'0000';const err=await rpc(db,'start_ride',{request_id:key(),id:ride.id,revision:r.revision,code:faux});assert.equal(err.error,'Code incorrect');assert.equal(err.essais_restants,4);
  await actor(db,A.client);await assert.rejects(rpc(db,'start_ride',{request_id:key(),id:ride.id,revision:r.revision,code}),/Chauffeur assigné requis/);
  await actor(db,A.driver);const parti=await rpc(db,'start_ride',{request_id:key(),id:ride.id,revision:r.revision,code});assert.equal(parti.statut,'Course en cours');
  await actor(db,A.client);assert.equal((await rpc(db,'ride_code',{id:ride.id})).code,null,'code masqué après le départ');
  await assert.rejects(rpc(db,'rate_ride',{id:ride.id,rating:5}),/après la course/);
  await avancer(db,ride,'Terminée');
  await actor(db,A.driver);await assert.rejects(rpc(db,'rate_ride',{id:ride.id,rating:5}),/réservée au client/);
  await actor(db,A.client);
  await assert.rejects(rpc(db,'rate_ride',{id:ride.id,rating:6}),/1 à 5/);await assert.rejects(rpc(db,'rate_ride',{id:ride.id,rating:4,tags:['Inventé']}),/inconnue/);
  assert.deepEqual(await rpc(db,'rate_ride',{id:ride.id,rating:4,tags:['Ponctuel','Courtois'],comment:'  Très bien  '}),{ok:true});
  await assert.rejects(rpc(db,'rate_ride',{id:ride.id,rating:5}),/déjà notée/);
  const proches=await rpc(db,'nearby_drivers',{category:'Taxi',start:point});const moi=proches.find(x=>x.driver_id===f.driver.id);assert.equal(Number(moi.rating),4);assert.equal(Number(moi.rating_count),1);
  assert.deepEqual(await rpc(db,'report_ride',{id:ride.id,motif:'Sécurité',details:'Conduite rapide'}),{ok:true});
  await assert.rejects(rpc(db,'report_ride',{id:ride.id,motif:'Inventé'}),/invalide/);
  await actor(db,A.other);await assert.rejects(rpc(db,'report_ride',{id:ride.id,motif:'Autre'}),/participants/);
  await actor(db,A.driver);const stats=await rpc(db,'driver_stats',{});assert.equal(Number(stats.courses_jour),1);assert.ok(Number(stats.montant_jour)>0);assert.equal(Number(stats.note),4);
  await actor(db,A.admin,'aal1');await assert.rejects(rpc(db,'admin_ride_reports',{}),/MFA/);
  await actor(db,A.admin,'aal2');const rep=await rpc(db,'admin_ride_reports',{});assert.equal(rep.length,1);assert.equal(rep[0].motif,'Sécurité');assert.equal(rep[0].role,'client');
  await actor(db,null,'aal1','anon');await assert.rejects(rpc(db,'ride_code',{id:ride.id}),/Compte permanent/);
 }finally{await db.close?.();}
});
test('demande sans réponse : expirée après 2 minutes, annulée avant une nouvelle réservation',async()=>{
 const db=await base();
 try{
  await setupBusinessDB(db);const f=await fixtureBusiness(db);
  const ride=await reserver(db,f);
  await db.query('reset role');await db.query("set session_replication_role=replica");await db.query("update public.koki_records set created_at=now()-interval '3 minutes' where id=$1",[ride.id]);await db.query("set session_replication_role=origin");
  await assert.rejects(avancer(db,ride,'Acceptée'),/Demande expirée/,'acceptation trop tardive refusée');
  const nouvelle=await reserver(db,f);assert.equal(nouvelle.statut,'En attente','nouvelle demande possible');
  await db.query('reset role');const ancienne=(await db.query('select statut,payload from public.koki_records where id=$1',[ride.id])).rows[0];
  assert.equal(ancienne.statut,'Annulée');assert.equal((typeof ancienne.payload==='string'?JSON.parse(ancienne.payload):ancienne.payload).expiree,true);
  // Les autres commandes passent toujours par le routeur habituel.
  await actor(db,A.client);assert.ok(Array.isArray(await rpc(db,'catalog',{})));
 }finally{await db.close?.();}
});
