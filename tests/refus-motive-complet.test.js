// Refus motivé sur tous les chemins de décision (audit du 14/10/2026, proposition refus-motive-complet.sql) :
// ancienne décision review_merchant, inscription chauffeur, suspension d'une inscription en attente,
// mise à jour directe de la table. Les suspensions de fiches déjà en ligne restent possibles sans motif.
import test from 'node:test';import assert from 'node:assert/strict';import {randomUUID as key} from 'node:crypto';
import {setupBusinessDB,actor,rpc,testActors as A,point} from './helpers/business-db.js';
async function base(){
 if(process.env.KOKI_DB_ADAPTER){const {psqlDB}=await import(process.env.KOKI_DB_ADAPTER);return psqlDB(process.env.KOKI_DB_NAME);}
 const {PGlite}=await import('@electric-sql/pglite');const pg=new PGlite();return {query:(q,v)=>v?pg.query(q,v):pg.exec(q).then(x=>x.at(-1)),close:()=>pg.close()};
}
const MOTIF=/Motif de refus obligatoire/;
test('chauffeur : refus uniquement par l’administration Transport, avec motif visible, réversible',async()=>{
 const db=await base();
 try{
  await setupBusinessDB(db);
  await actor(db,A.driver);const c=await rpc(db,'register_driver',{request_id:key(),name:'Chauffeur TEST',phone:'+221701234567'});assert.equal(c.statut,'À valider');
  // Le chauffeur ne peut ni se refuser ni se valider ; un client non plus ; un administrateur sans MFA non plus.
  for(const decision of ['approve','reject'])await assert.rejects(rpc(db,'admin_review',{request_id:key(),id:c.id,decision,note:'Motif TEST'}));
  await actor(db,A.client);await assert.rejects(rpc(db,'admin_review',{request_id:key(),id:c.id,decision:'reject',note:'Motif TEST'}));
  await actor(db,A.admin,'aal1');await assert.rejects(rpc(db,'admin_review',{request_id:key(),id:c.id,decision:'reject',note:'Motif TEST'}),/MFA/);
  await actor(db,A.editor,'aal2');await assert.rejects(rpc(db,'admin_review',{request_id:key(),id:c.id,decision:'reject',note:'Motif TEST'}),/Transport|MFA/);
  // Administrateur Transport : motif obligatoire (3 caractères), y compris pour une « suspension » d'inscription en attente.
  await actor(db,A.admin,'aal2');
  for(const note of [undefined,'',' ','ok'])await assert.rejects(rpc(db,'admin_review',{request_id:key(),id:c.id,decision:'reject',...(note===undefined?{}:{note})}),MOTIF);
  await assert.rejects(rpc(db,'admin_review',{request_id:key(),id:c.id,decision:'reject',note:'x'.repeat(501)}),/trop long/);
  await assert.rejects(rpc(db,'admin_review',{request_id:key(),id:c.id,decision:'suspend'}),MOTIF);
  const k=key(),refus=await rpc(db,'admin_review',{request_id:k,id:c.id,decision:'reject',note:'  Permis illisible  '});
  assert.equal(refus.statut,'Suspendu');assert.deepEqual([refus.payload.moderation.decision,refus.payload.moderation.note],['reject','Permis illisible']);
  assert.deepEqual(await rpc(db,'admin_review',{request_id:k,id:c.id,decision:'reject',note:'  Permis illisible  '}),refus,'nouvel essai idempotent');
  await assert.rejects(rpc(db,'admin_review',{request_id:key(),id:c.id,decision:'reject',note:'Deuxième refus'}),/incompatible/);
  // Le chauffeur voit le motif et ne peut pas se rendre disponible.
  await actor(db,A.driver);const vue=await rpc(db,'get',{id:c.id});assert.equal(vue.payload.moderation.note,'Permis illisible');
  await assert.rejects(rpc(db,'driver_position',{request_id:key(),position:point,available:true}));
  // L'administration peut revenir sur sa décision.
  await actor(db,A.admin,'aal2');const ok=await rpc(db,'admin_review',{request_id:key(),id:c.id,decision:'approve'});assert.equal(ok.statut,'Indisponible');
  // Suspension d'un chauffeur déjà validé : inchangée (pas un refus d'inscription).
  assert.equal((await rpc(db,'admin_review',{request_id:key(),id:c.id,decision:'suspend'})).statut,'Suspendu');
 }finally{await db.close?.();}
});
test('administrateur chauffeur : ne peut pas refuser ni valider sa propre inscription',async()=>{
 const db=await base();
 try{
  await setupBusinessDB(db);
  await actor(db,A.admin,'aal2');const c=await rpc(db,'register_driver',{request_id:key(),name:'Admin chauffeur TEST',phone:'+221701234568'});
  for(const decision of ['approve','reject'])await assert.rejects(rpc(db,'admin_review',{request_id:key(),id:c.id,decision,note:'Motif TEST'}),/propres fiches/);
 }finally{await db.close?.();}
});
test('professionnels : pas de refus de fait sans motif, suspensions de fiches en ligne inchangées',async()=>{
 const db=await base();
 try{
  await setupBusinessDB(db);
  await actor(db,A.merchant);const f=await rpc(db,'save_profile',{request_id:key(),name:'Épicerie TEST',profile:'Commerçant',category:'Alimentation',phone:'+221771234567',village:'Coki'});
  assert.equal(f.statut,'En attente');
  await actor(db,A.admin,'aal2');
  await assert.rejects(rpc(db,'admin_review',{request_id:key(),id:f.id,decision:'suspend'}),MOTIF,'suspension d’une inscription en attente = refus sans motif');
  await assert.rejects(rpc(db,'moderate',{request_id:key(),id:f.id,revision:f.revision,decision:'reject',note:'no'}),MOTIF);
  const ok=await rpc(db,'moderate',{request_id:key(),id:f.id,revision:f.revision,decision:'approve'});assert.equal(ok.statut,'Actif');
  assert.equal((await rpc(db,'admin_review',{request_id:key(),id:f.id,decision:'suspend'})).statut,'Suspendu','suspension d’une fiche en ligne sans motif : inchangée');
  // Garde-fou de dernier recours, même pour une écriture directe privilégiée.
  await db.query('reset role');
  await actor(db,A.driver);const c=await rpc(db,'register_driver',{request_id:key(),name:'Chauffeur TEST',phone:'+221701234569'});await db.query('reset role');
  await assert.rejects(db.query("update public.koki_records set statut='Suspendu' where id=$1",[c.id]),MOTIF);
  await assert.rejects(db.query("update public.koki_records set statut='Refusé' where id=$1",[f.id]),MOTIF);
  await db.query("update public.koki_records set statut='Suspendu',payload=payload||jsonb_build_object('moderation',jsonb_build_object('decision','reject','note','Motif TEST','at',now())) where id=$1",[c.id]);
 }finally{await db.close?.();}
});
test('écran chauffeurs : refus d’inscription avec motif obligatoire transmis au serveur',async()=>{
 const {readFile}=await import('node:fs/promises');const src=await readFile(new URL('../src/business-admin.js',import.meta.url),'utf8');
 assert.match(src,/\['Refuser l’inscription','reject'\]/);
 assert.match(src,/decision==='reject'&&texte\.length<3/,'motif vérifié avant l’envoi');
 assert.match(src,/decision==='reject'\?\{note:texte\}/,'motif transmis au serveur');
 assert.match(src,/Motif indiqué : /,'motif précédent affiché');
});
