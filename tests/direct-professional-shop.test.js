import test from 'node:test';import assert from 'node:assert/strict';import {PGlite} from '@electric-sql/pglite';import {readFile} from 'node:fs/promises';
import {setupBusinessDB,actor,rpc,testActors as A} from './helpers/business-db.js';
test('boutique immédiate : reprise, gestion avant validation, catalogue protégé et aucun doublon',async()=>{
 const pg=new PGlite(),db={query:(q,v)=>v?pg.query(q,v):pg.exec(q).then(x=>x.at(-1))};const key=()=>crypto.randomUUID();
 try{await setupBusinessDB(db);for(const name of ['commerce-desarchiver-proprietaire.sql','commerce-boutique-des-envoi-fiche.sql'])await db.query(await readFile(new URL('../supabase/proposals/'+name,import.meta.url),'utf8'));await actor(db,A.merchant);
 const legacy=await rpc(db,'register_professional',{request_id:key(),name:'TEST Legacy',phone:'+221771234567',profile:'Commerçant'});
 await actor(db,A.admin,'aal2');await rpc(db,'admin_review',{request_id:key(),id:legacy.id,decision:'approve'});
 await db.query('reset role');await db.query(await readFile(new URL('../supabase/proposals/direct-professional-shop.sql',import.meta.url),'utf8'));
 const shops=async id=>(await db.query("select * from public.koki_records where kind='boutiques' and parent_id=$1",[id])).rows;
 assert.equal((await shops(legacy.id)).length,1);
 await actor(db,A.provider);const request={request_id:key(),name:'TEST Nouveau',phone:'+221771234568',profile:'Commerçant'};
 const profile=await rpc(db,'register_professional',request);assert.equal((await rpc(db,'register_professional',request)).id,profile.id);
 const [shop]=await shops(profile.id);assert.ok(shop);assert.equal(shop.owner_id,A.provider);assert.equal(shop.payload.nom,profile.payload.nom);
 const product=await rpc(db,'save_product',{request_id:key(),parent_id:shop.id,name:'TEST Assiette',price:1000,stock:4});
 const updated=await rpc(db,'save_product',{request_id:key(),id:product.id,revision:product.revision,parent_id:shop.id,name:'TEST Assiette',price:1500,stock:3});assert.equal(updated.payload.stock,3);
 assert.ok(!JSON.stringify(await rpc(db,'catalog')).includes(product.id),'aucune offre publique avant validation');
 await actor(db,A.other);await assert.rejects(rpc(db,'save_product',{request_id:key(),parent_id:shop.id,name:'Intrusion',price:1,stock:1}),/Propriétaire/);
 await actor(db,A.admin,'aal2');await rpc(db,'admin_review',{request_id:key(),id:profile.id,decision:'approve'});
 assert.equal((await shops(profile.id)).length,1);assert.ok(JSON.stringify(await rpc(db,'catalog')).includes(product.id),'une seule validation publie le catalogue');
 await actor(db,A.provider);await rpc(db,'archive',{request_id:key(),id:updated.id,revision:updated.revision});assert.ok(!JSON.stringify(await rpc(db,'catalog')).includes(product.id));
 await rpc(db,'archive',{request_id:key(),id:shop.id,revision:shop.revision});
 await db.query('reset role');await db.query('select koki_private.ensure_initial_shop(p) from public.koki_records p where id=$1',[profile.id]);assert.equal((await shops(profile.id)).length,1);assert.equal((await shops(profile.id))[0].statut,'Archivé');
 }finally{await pg.close();}
});
