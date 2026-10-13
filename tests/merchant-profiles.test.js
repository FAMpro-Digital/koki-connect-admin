import test from 'node:test';import assert from 'node:assert/strict';import {PGlite} from '@electric-sql/pglite';import {randomUUID} from 'node:crypto';import {setupBusinessDB,actor,rpc,testActors} from './helpers/business-db.js';
const input=()=>({request_id:randomUUID(),name:'TEST Commerce',profile:'Commerçant',category:'Alimentation',phone:'+221770000000',address:'TEST Koki marché',location:{latitude:15.5,longitude:-16},hours:'Lundi au samedi 8h–18h',description:'TEST commerce local pour les essais uniquement',photos:[]});
async function fixture(fn){const pg=new PGlite(),db={query:(q,v)=>v?pg.query(q,v):pg.exec(q).then(x=>x.at(-1))};try{await setupBusinessDB(db);await actor(db,testActors.merchant);await fn(db);}finally{await pg.close();}}
test('fiche commerçant : attente, relecture, refus, correction, validation et revalidation sans retrait',()=>fixture(async db=>{
 const body=input(),saved=await rpc(db,'submit_merchant',body);assert.equal(saved.statut,'En attente');assert.equal(saved.owner_id,testActors.merchant);assert.deepEqual((await rpc(db,'submit_merchant',body)).id,saved.id);assert.equal((await rpc(db,'get',{id:saved.id})).payload.horaires,body.hours);
 await actor(db,null,'aal1','anon');assert.equal((await rpc(db,'catalog')).length,0);
 await actor(db,testActors.admin,'aal1');await assert.rejects(rpc(db,'review_merchant',{request_id:randomUUID(),id:saved.id,revision:saved.revision,decision:'approve'}),/MFA/);
 await actor(db,testActors.editor,'aal2');await assert.rejects(rpc(db,'review_merchant',{request_id:randomUUID(),id:saved.id,revision:saved.revision,decision:'approve'}),/MFA/);
 await actor(db,testActors.admin,'aal2');const denied=await rpc(db,'review_merchant',{request_id:randomUUID(),id:saved.id,revision:saved.revision,decision:'reject'});assert.equal(denied.statut,'Refusé');
 await actor(db,testActors.merchant);const amended=await rpc(db,'submit_merchant',{...input(),id:saved.id,revision:denied.revision});assert.equal(amended.statut,'En attente');
 await actor(db,testActors.admin,'aal2');await assert.rejects(rpc(db,'review_merchant',{request_id:randomUUID(),id:saved.id,revision:saved.revision,decision:'approve'}),/périmée/);
 const approved=await rpc(db,'review_merchant',{request_id:randomUUID(),id:saved.id,revision:amended.revision,decision:'approve'});assert.equal(approved.statut,'Actif');
 await actor(db,null,'aal1','anon');const rows=await rpc(db,'catalog');assert.equal(rows.length,1);assert.equal(rows[0].horaires,body.hours);assert.deepEqual(rows[0].localisation,body.location);assert.equal(rows[0].owner_id,undefined);assert.equal(rows[0].merchant_submission,undefined);
 // Phase 4 : une modification d'une fiche en ligne attend sa validation sans retirer la fiche du catalogue.
 await actor(db,testActors.merchant);const edit=await rpc(db,'submit_merchant',{...input(),id:saved.id,revision:approved.revision,name:'TEST Nouveau nom'});assert.equal(edit.statut,'Actif');assert.equal(edit.payload.modification.nom,'TEST Nouveau nom');
 await actor(db,null,'aal1','anon');const still=await rpc(db,'catalog');assert.equal(still.length,1);assert.notEqual(still[0].nom,'TEST Nouveau nom');
}));
test('fiches : champs inconnus, propriétaire, médias, GPS et ancien accès privé contrôlés',()=>fixture(async db=>{
 await assert.rejects(rpc(db,'submit_merchant',{...input(),statut:'Actif'}),/Champs inconnus/);
 await assert.rejects(rpc(db,'submit_merchant',{...input(),owner_id:testActors.admin}),/Champs inconnus/);
 await actor(db,null,'aal1','anon');await assert.rejects(rpc(db,'submit_merchant',input()),/Compte permanent/);await actor(db,testActors.merchant);
 await assert.rejects(rpc(db,'submit_merchant',{...input(),location:{latitude:91,longitude:0}}),/GPS/);
 await assert.rejects(rpc(db,'submit_merchant',{...input(),phone:'javascript:alert(1)'}),/invalide/);
 await assert.rejects(rpc(db,'submit_merchant',{...input(),photos:['https://evil.invalid/photo.jpg']}),/Photo privée/);
 await assert.rejects(rpc(db,'submit_merchant',{...input(),photos:Array(6).fill('x')}),/Cinq/);
 const saved=await rpc(db,'submit_merchant',input());await actor(db,testActors.other);assert.equal((await db.query('select id from public.koki_records')).rows.length,0);await assert.rejects(rpc(db,'get',{id:saved.id}),/refusé/);await assert.rejects(rpc(db,'submit_merchant',{...input(),id:saved.id,revision:saved.revision}),/inaccessible/);
 await assert.rejects(db.query("select koki_private.business('catalog','{}')"),/permission denied/);
 await actor(db,testActors.admin,'aal2');await assert.rejects(rpc(db,'admin_review',{request_id:randomUUID(),id:saved.id,decision:'approve'}),/périmée/);
}));
test('photos commerçant : privées avant validation, galerie publique approuvée, référence protégée',()=>fixture(async db=>{
 const photos=[`${testActors.merchant}/${randomUUID()}.jpg`,`${testActors.merchant}/${randomUUID()}.webp`];await db.query('reset role');for(const path of photos)await db.query("insert into storage.objects(bucket_id,name) values('koki-media',$1)",[path]);await actor(db,testActors.merchant);
 const saved=await rpc(db,'submit_merchant',{...input(),photos});await actor(db,null,'aal1','anon');assert.equal((await db.query('select name from storage.objects')).rows.length,0);
 await actor(db,testActors.admin,'aal2');assert.equal((await db.query('select name from storage.objects')).rows.length,2);const approved=await rpc(db,'review_merchant',{request_id:randomUUID(),id:saved.id,revision:saved.revision,decision:'approve'});
 await actor(db,null,'aal1','anon');assert.equal((await db.query('select name from storage.objects')).rows.length,2);assert.deepEqual((await rpc(db,'catalog'))[0].photos,photos);
 await actor(db,testActors.merchant);assert.equal((await db.query('delete from storage.objects returning name')).rows.length,0);
 await actor(db,testActors.admin,'aal2');await rpc(db,'review_merchant',{request_id:randomUUID(),id:saved.id,revision:approved.revision,decision:'suspend'});await actor(db,null,'aal1','anon');assert.equal((await db.query('select name from storage.objects')).rows.length,0);assert.equal((await rpc(db,'catalog')).length,0);
}));
