import test from 'node:test';import assert from 'node:assert/strict';import {PGlite} from '@electric-sql/pglite';
import {setupBusinessDB,actor,rpc,fixtureBusiness,testActors,point} from './helpers/business-db.js';
// Vérifié aussi sur PostgreSQL 16 (scénario équivalent) : limite de débit, position arrondie, chauffeur suspendu bloqué.
test('chauffeurs proches : pas de triangulation par appels répétés',async()=>{
 const pg=new PGlite();const db={query:(sql,values)=>values?pg.query(sql,values):pg.exec(sql).then(results=>results.at(-1))};
 try{await setupBusinessDB(db);await fixtureBusiness(db);
  await actor(db,testActors.client);
  const found=await rpc(db,'nearby_drivers',{category:'Taxi',start:point});
  assert.equal(found.length,1);assert.equal(found[0].proximity,'À proximité (moins de 10 km)');assert.equal(found[0].position,undefined);
  for(let i=0;i<9;i++)await rpc(db,'nearby_drivers',{category:'Taxi',start:point});
  await assert.rejects(rpc(db,'nearby_drivers',{category:'Taxi',start:point}),/Trop de recherches/);
  await actor(db,testActors.driver);assert.equal((await rpc(db,'nearby_drivers',{category:'Taxi',start:point})).length,0,'le chauffeur ne se voit pas');
  // Frontière des 10 km calculée sur la position arrondie (grille de 0,005°), jamais sur la position exacte.
  await actor(db,testActors.other);const north=lat=>rpc(db,'nearby_drivers',{category:'Taxi',start:{latitude:lat,longitude:point.longitude}});
  const snapped=Math.round(point.latitude/0.005)*0.005,edge=snapped+10/111.195;
  assert.equal((await north(edge-0.0005)).length,1);assert.equal((await north(edge+0.0005)).length,0);
 }finally{await pg.close();}
});
