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
  const refuser=(extra={})=>({request_id:key(),id:c.id,revision:c.revision,decision:'reject',note:'Motif TEST',...extra});
  // Le chauffeur ne peut ni se refuser ni se valider ; un client non plus ; un administrateur sans MFA non plus.
  await assert.rejects(rpc(db,'admin_review',refuser()),/propres fiches/,'auto-refus interdit');
  await assert.rejects(rpc(db,'admin_review',{request_id:key(),id:c.id,decision:'approve'}),/propres fiches/,'auto-validation interdite');
  await actor(db,A.client);await assert.rejects(rpc(db,'admin_review',refuser()));
  await actor(db,A.admin,'aal1');await assert.rejects(rpc(db,'admin_review',refuser()),/MFA/);
  await actor(db,A.editor,'aal2');await assert.rejects(rpc(db,'admin_review',refuser()),/Transport|MFA/);
  // Administrateur Transport : motif obligatoire (3 caractères), y compris pour une « suspension » d'inscription en attente.
  await actor(db,A.admin,'aal2');
  for(const note of [undefined,'',' ','ok','  a  '])await assert.rejects(rpc(db,'admin_review',refuser({note})),MOTIF,'motif absent ou trop court : '+JSON.stringify(note));
  await assert.rejects(rpc(db,'admin_review',refuser({note:'x'.repeat(501)})),/trop long/);
  await assert.rejects(rpc(db,'admin_review',{request_id:key(),id:c.id,decision:'suspend'}),MOTIF);
  // Révision : obligatoire, et une révision périmée est rejetée.
  await assert.rejects(rpc(db,'admin_review',refuser({revision:undefined})),/périmée/,'révision absente');
  await assert.rejects(rpc(db,'admin_review',refuser({revision:c.revision+1})),/périmée/,'révision périmée');
  await assert.rejects(rpc(db,'admin_review',refuser({statut:'Disponible'})),/Champs inconnus/);
  const k=key(),refus=await rpc(db,'admin_review',refuser({request_id:k,note:'  Permis illisible  '}));
  assert.equal(refus.statut,'Suspendu');assert.deepEqual([refus.payload.moderation.decision,refus.payload.moderation.note],['reject','Permis illisible']);
  assert.ok(refus.revision>c.revision,'révision incrémentée');
  assert.deepEqual(await rpc(db,'admin_review',refuser({request_id:k,note:'  Permis illisible  '})),refus,'nouvel essai idempotent (même request_id)');
  await assert.rejects(rpc(db,'admin_review',refuser({request_id:k,note:'Autre motif'})),/Clé déjà utilisée/,'request_id réutilisé pour une autre requête');
  await assert.rejects(rpc(db,'admin_review',refuser({note:'Deuxième refus'})),/périmée/,'ancienne révision après le refus');
  await assert.rejects(rpc(db,'admin_review',refuser({revision:refus.revision,note:'Deuxième refus'})),/incompatible/,'déjà refusé');
  // Le chauffeur voit le motif et ne peut pas se rendre disponible.
  await actor(db,A.driver);const vue=await rpc(db,'get',{id:c.id});assert.equal(vue.statut,'Suspendu');assert.equal(vue.payload.moderation.note,'Permis illisible');
  await assert.rejects(rpc(db,'driver_position',{request_id:key(),position:point,available:true}));
  // L'administration peut revenir sur sa décision.
  await actor(db,A.admin,'aal2');const ok=await rpc(db,'admin_review',{request_id:key(),id:c.id,decision:'approve'});assert.equal(ok.statut,'Indisponible');
  // Suspension d'un chauffeur déjà validé : inchangée (pas un refus d'inscription), puis réactivation.
  assert.equal((await rpc(db,'admin_review',{request_id:key(),id:c.id,decision:'suspend'})).statut,'Suspendu');
  assert.equal((await rpc(db,'admin_review',{request_id:key(),id:c.id,decision:'approve'})).statut,'Indisponible');
  // Refus impossible sur une autre fiche que « chauffeurs » ou une fiche inexistante.
  await assert.rejects(rpc(db,'admin_review',refuser({id:'00000000-0000-4000-8000-000000000000'})));
 }finally{await db.close?.();}
});
test('administrateur chauffeur : ni auto-refus ni auto-validation, même en contournant le routeur Commerce',async()=>{
 const db=await base();
 try{
  await setupBusinessDB(db);
  await actor(db,A.admin,'aal2');const c=await rpc(db,'register_driver',{request_id:key(),name:'Admin chauffeur TEST',phone:'+221701234568'});
  await assert.rejects(rpc(db,'admin_review',{request_id:key(),id:c.id,revision:c.revision,decision:'reject',note:'Motif TEST'}),/propres fiches/,'auto-refus');
  await assert.rejects(rpc(db,'admin_review',{request_id:key(),id:c.id,decision:'approve'}),/propres fiches/,'auto-validation');
  // Défense en profondeur : appel direct de merchant_business (même identité, MFA), sans passer par commerce_admin.
  await db.query('reset role');
  const direct=(i)=>db.query('select koki_private.merchant_business($1,$2::jsonb) r',['admin_review',JSON.stringify(i)]);
  await assert.rejects(direct({request_id:key(),id:c.id,revision:c.revision,decision:'reject',note:'Motif TEST'}),/propres fiches/,'auto-refus direct');
  await assert.rejects(direct({request_id:key(),id:c.id,decision:'approve'}),/propres fiches/,'auto-validation directe');
  assert.equal((await db.query('select statut from public.koki_records where id=$1',[c.id])).rows[0].statut,'À valider','inscription inchangée');
 }finally{await db.close?.();}
});
test('script de production = proposition testée, encadrée par la garde',async()=>{
 const {readFile}=await import('node:fs/promises');const lire=n=>readFile(new URL('../supabase/'+n,import.meta.url),'utf8');
 const prop=await lire('proposals/refus-motive-complet.sql'),prod=await lire('production/refus-motive-complet.sql');
 assert.ok(prod.includes(prop),'le script de production contient la proposition à l’identique');
 assert.match(prod,/^begin;$/m);assert.match(prod,/^commit;$/m);assert.match(prod,/525819041eed1710d0dbc44e62721c4d/);
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
 assert.match(src,/merchant\|\|decision==='reject'\?\{revision:row\.revision\}/,'révision transmise avec le refus');
 assert.match(src,/Motif indiqué : /,'motif précédent affiché');
});
