// Parcours professionnel : statut « En attente » après envoi, aucune publication sans approbation,
// décisions (approbation, refus motivé) réservées à l'administration avec double authentification.
import test from 'node:test';import assert from 'node:assert/strict';import {randomUUID as key} from 'node:crypto';
import {setupBusinessDB,actor,rpc,testActors as A,point} from './helpers/business-db.js';
async function base(){
 if(process.env.KOKI_DB_ADAPTER){const {psqlDB}=await import(process.env.KOKI_DB_ADAPTER);return psqlDB(process.env.KOKI_DB_NAME);}
 const {PGlite}=await import('@electric-sql/pglite');const pg=new PGlite();return {query:(q,v)=>v?pg.query(q,v):pg.exec(q).then(x=>x.at(-1)),close:()=>pg.close()};
}
const fiche=(profile,name)=>({request_id:key(),name,profile,category:profile==='Commerçant'?'Alimentation':'Plomberie',phone:'+221771234567',village:'Coki'});
test('professionnel non approuvé : rien n’est publié, seules les décisions de l’administration ouvrent le catalogue',async()=>{
 const db=await base();
 try{
  await setupBusinessDB(db);
  // Envoi : statut « En attente », invisible dans le catalogue.
  await actor(db,A.merchant);const f=await rpc(db,'save_profile',fiche('Commerçant','Épicerie en attente TEST'));
  assert.equal(f.statut,'En attente');
  await actor(db,null,'aal1','anon');assert.ok(!(await rpc(db,'catalog')).some(x=>x.id===f.id));
  // Publication directe interdite tant que la fiche n'est pas approuvée.
  await actor(db,A.merchant);
  await assert.rejects(rpc(db,'save_shop',{request_id:key(),parent_id:f.id,name:'Boutique TEST',village:'Coki'}),'boutique refusée avant approbation de la fiche');
  await assert.rejects(rpc(db,'moderate',{request_id:key(),id:f.id,revision:f.revision,decision:'approve'}),'le professionnel ne peut pas s’approuver');
  await assert.rejects(db.query("update public.koki_records set statut='Actif' where id=$1",[f.id]),'aucune écriture directe dans la table');
  // Un client ordinaire n'a aucun droit d'administration.
  await actor(db,A.client);
  for(const [c,i] of [['admin_queue',{}],['moderate',{request_id:key(),id:f.id,revision:f.revision,decision:'approve'}],['admin_review',{request_id:key(),id:f.id,decision:'approve'}],['set_rate',{request_id:key(),category:'Moto',base_fcfa:1,per_km_fcfa:1,active:true}]])await assert.rejects(rpc(db,c,i),c+' refusé à un client');
  // Administrateur sans double authentification : refusé.
  await actor(db,A.admin,'aal1');await assert.rejects(rpc(db,'moderate',{request_id:key(),id:f.id,revision:f.revision,decision:'approve'}),/MFA/);
  // Refus motivé : motif obligatoire, visible par le professionnel, fiche toujours invisible.
  await actor(db,A.admin,'aal2');
  await assert.rejects(rpc(db,'moderate',{request_id:key(),id:f.id,revision:f.revision,decision:'reject'}),'refus sans motif impossible');
  const refuse=await rpc(db,'moderate',{request_id:key(),id:f.id,revision:f.revision,decision:'reject',note:'Photo de la devanture manquante'});
  assert.equal(refuse.statut,'Refusé');
  await actor(db,A.merchant);const vue=(await rpc(db,'get',{id:f.id}));assert.equal(vue.payload.moderation?.note,'Photo de la devanture manquante');
  await assert.rejects(rpc(db,'save_shop',{request_id:key(),parent_id:f.id,name:'Boutique TEST',village:'Coki'}));
  // Correction et nouvel envoi : de nouveau en attente, puis approbation.
  const corrige=await rpc(db,'save_profile',{...fiche('Commerçant','Épicerie corrigée TEST'),id:f.id,revision:vue.revision});assert.equal(corrige.statut,'En attente');
  await actor(db,A.admin,'aal2');const ok=await rpc(db,'moderate',{request_id:key(),id:f.id,revision:corrige.revision,decision:'approve'});assert.equal(ok.statut,'Actif');
  // Boutique en attente : produits impossibles ; boutique approuvée : produits publiés.
  await actor(db,A.merchant);const b=await rpc(db,'save_shop',{request_id:key(),parent_id:f.id,name:'Boutique TEST',village:'Coki'});assert.notEqual(b.statut,'Actif');
  await assert.rejects(rpc(db,'save_product',{request_id:key(),parent_id:b.id,name:'Riz TEST',price:500,stock:2}),'produit refusé dans une boutique non approuvée');
  // Prestataire en attente : service impossible.
  await actor(db,A.provider);const s=await rpc(db,'save_profile',fiche('Prestataire de services','Plombier en attente TEST'));assert.equal(s.statut,'En attente');
  await assert.rejects(rpc(db,'save_service',{request_id:key(),parent_id:s.id,name:'Fuite TEST',category:'Plomberie',pricing:'devis'}));
  // Chauffeur « À valider » : pas de disponibilité, pas proposé aux clients.
  await actor(db,A.driver);const c=await rpc(db,'register_driver',{request_id:key(),name:'Chauffeur TEST',phone:'+221701234567'});assert.equal(c.statut,'À valider');
  await rpc(db,'save_vehicle',{request_id:key(),parent_id:c.id,name:'Moto TEST',category:'Moto',registration:'DK-1-TEST'});
  await assert.rejects(rpc(db,'driver_position',{request_id:key(),position:point,available:true}),/Chauffeur validé requis/);
  await assert.rejects(rpc(db,'admin_review',{request_id:key(),id:c.id,decision:'approve'}),'le chauffeur ne peut pas se valider');
 }finally{await db.close?.();}
});
