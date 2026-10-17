import test from 'node:test';import assert from 'node:assert/strict';import {PGlite} from '@electric-sql/pglite';import {randomUUID} from 'node:crypto';import {readFile} from 'node:fs/promises';
import {setupBusinessDB,fixtureBusiness,actor,rpc,testActors} from './helpers/business-db.js';
test('produit masqué jusqu’à approbation avec MFA, sans changement des produits existants',async()=>{
 const pg=new PGlite(),db={query:(q,v)=>v?pg.query(q,v):pg.exec(q).then(x=>x.at(-1))};
 try{
 await setupBusinessDB(db);const f=await fixtureBusiness(db);await db.query('reset role');await db.query(await readFile(new URL('../supabase/proposals/produits-validation.sql',import.meta.url),'utf8'));
 await actor(db,testActors.merchant);const p=await rpc(db,'save_product',{request_id:randomUUID(),parent_id:f.shop.id,name:'Nouveau riz à valider',price:500,stock:5});
 assert.equal(p.statut,'Masqué');assert.equal(p.payload.moderation.decision,'pending_review');assert.equal(p.payload.moderation_lock,true);
 await assert.rejects(rpc(db,'set_availability',{request_id:randomUUID(),id:p.id,revision:p.revision,status:'Disponible'}));
 await actor(db,testActors.other);assert.equal((await db.query('select id from public.koki_records where id=$1',[p.id])).rows.length,0);
 await actor(db,null,'aal1','anon');assert.ok(!JSON.stringify(await rpc(db,'catalog')).includes(p.id));assert.ok(JSON.stringify(await rpc(db,'catalog')).includes(f.product.id));
 for(const [who,aal] of [[testActors.merchant,'aal2'],[testActors.editor,'aal2'],[testActors.admin,'aal1']]){await actor(db,who,aal);await assert.rejects(rpc(db,'moderate',{request_id:randomUUID(),id:p.id,revision:p.revision,decision:'approve'}));}
 await actor(db,testActors.admin,'aal2');const queue=await rpc(db,'admin_queue');assert.equal(queue.find(x=>x.id===p.id)?.demande,'produit');assert.equal((await rpc(db,'admin_stats')).produits_en_attente,1);
 const approved=await rpc(db,'moderate',{request_id:randomUUID(),id:p.id,revision:p.revision,decision:'approve'});assert.equal(approved.statut,'Disponible');assert.equal(approved.payload.moderation_lock,false);assert.ok(!(await rpc(db,'admin_queue')).some(x=>x.id===p.id));
 await actor(db,null,'aal1','anon');assert.ok(JSON.stringify(await rpc(db,'catalog')).includes(p.id));
 }finally{await pg.close();}
});
