// Parcours complet, tel que l'application publique et l'admin l'enchaînent (mêmes commandes koki_business) :
// commerçant → fiche → validation → boutique → validation → produit → commande client → retrait ;
// prestataire → fiche → validation → service → demande de devis → devis accepté → service terminé ;
// chauffeur → inscription → véhicule → validation → tarif → disponibilité → estimation → course → terminée.
import test from 'node:test';import assert from 'node:assert/strict';import {randomUUID as key} from 'node:crypto';
import {setupBusinessDB,actor,rpc,testActors as A,point,destination} from './helpers/business-db.js';
async function base(){
 if(process.env.KOKI_DB_ADAPTER){const {psqlDB}=await import(process.env.KOKI_DB_ADAPTER);return psqlDB(process.env.KOKI_DB_NAME);}
 const {PGlite}=await import('@electric-sql/pglite');const pg=new PGlite();return {query:(q,v)=>v?pg.query(q,v):pg.exec(q).then(x=>x.at(-1)),close:()=>pg.close()};
}
const admin=async db=>actor(db,A.admin,'aal2');
async function valider(db,row){await admin(db);const queue=await rpc(db,'admin_queue',{});assert.ok(queue.some(x=>x.id===row.id),'« '+row.payload.nom+' » dans la file de validation');return rpc(db,'moderate',{request_id:key(),id:row.id,revision:row.revision,decision:'approve'});}
async function suivre(db,row,etapes){let r=row;for(const next of etapes)r=await rpc(db,'transition',{request_id:key(),id:r.id,revision:r.revision,next});return r;}

test('parcours complet : boutique en ligne, service, chauffeur',async()=>{
 const db=await base();
 try{
  await setupBusinessDB(db);
  // 1. Commerçant : fiche professionnelle (espace professionnel), validation, boutique, validation, produit.
  await actor(db,A.merchant);
  const fiche=await rpc(db,'save_profile',{request_id:key(),name:'Épicerie TEST',profile:'Commerçant',category:'Alimentation',phone:'+221771234567',whatsapp:'+221771234567',village:'Coki',address:'Près du marché',hours:'Lundi–samedi 8 h–20 h',description:'Épicerie de quartier TEST'});
  assert.notEqual(fiche.statut,'Actif','fiche en attente avant validation');
  await actor(db,null,'aal1','anon');assert.ok(!(await rpc(db,'catalog')).some(x=>x.id===fiche.id),'invisible avant validation');
  const ficheOk=await valider(db,fiche);assert.equal(ficheOk.statut,'Actif');
  await actor(db,A.merchant);
  const boutique=await rpc(db,'save_shop',{request_id:key(),parent_id:fiche.id,name:'Boutique du marché TEST',village:'Coki',whatsapp:'+221761234567'});
  const boutiqueOk=await valider(db,boutique);assert.equal(boutiqueOk.statut,'Actif');
  await actor(db,A.merchant);
  const riz=await rpc(db,'save_product',{request_id:key(),parent_id:boutique.id,name:'Riz 5 kg TEST',price:4500,old_price:5000,stock:8});
  assert.equal(riz.statut,'Disponible','produit publié directement après validation de la boutique');
  // 2. Catalogue public : commerce, boutique et produit visibles, promotion conservée.
  await actor(db,null,'aal1','anon');const cat=await rpc(db,'catalog');
  for(const id of [fiche.id,boutique.id,riz.id])assert.ok(cat.some(x=>x.id===id),id);
  assert.equal(cat.find(x=>x.id===riz.id).ancien_prix,5000);
  // 3. Client : commande (retrait), le commerçant la mène jusqu'au retrait ; stock décrémenté.
  await actor(db,A.client);
  const commande=await rpc(db,'create_order',{request_id:key(),shop_id:boutique.id,items:[{product_id:riz.id,quantity:2}],mode:'retrait'});
  assert.equal(commande.payload.total,9000);assert.equal(commande.statut,'Commande reçue');
  await actor(db,A.merchant);const retiree=await suivre(db,commande,['Confirmée','Préparation','Prête au retrait','Retirée']);assert.equal(retiree.statut,'Retirée');
  assert.equal((await rpc(db,'get',{id:riz.id})).payload.stock,6);
  await actor(db,A.client);assert.equal((await rpc(db,'history',{kind:'commandes'}))[0].statut,'Retirée');

  // 4. Prestataire : fiche, validation, service sur devis, demande, devis proposé puis accepté, service terminé.
  await actor(db,A.provider);
  const pro=await rpc(db,'save_profile',{request_id:key(),name:'Plombier TEST',profile:'Prestataire de services',category:'Plomberie',phone:'+221781234567',village:'Coki',zone:'Koki et villages voisins',description:'Dépannage plomberie TEST'});
  await valider(db,pro);await actor(db,A.provider);
  const service=await rpc(db,'save_service',{request_id:key(),parent_id:pro.id,name:'Réparation de fuite TEST',category:'Plomberie',pricing:'devis'});
  assert.equal(service.statut,'Disponible');
  await actor(db,null,'aal1','anon');assert.ok((await rpc(db,'catalog')).some(x=>x.id===service.id));
  await actor(db,A.client);const demande=await rpc(db,'request_service',{request_id:key(),service_id:service.id,need:'Fuite sous l’évier TEST',address:'Koki, quartier TEST',date:'2099-10-20'});
  await actor(db,A.provider);await rpc(db,'submit_service_quote',{request_id:key(),id:demande.id,revision:demande.revision,amount_fcfa:5000,description:'Remplacement du joint TEST'});
  await actor(db,A.client);const propose=await rpc(db,'get',{id:demande.id});const accepte=await rpc(db,'accept_service_quote',{request_id:key(),id:demande.id,revision:propose.revision});
  assert.equal(accepte.statut,'Acceptée');
  await actor(db,A.provider);const fini=await suivre(db,accepte,['Prestataire en route','Service en cours','Terminé']);assert.equal(fini.statut,'Terminé');

  // 5. Chauffeur : inscription, véhicule, validation, tarif publié, disponibilité, estimation, course, contacts, fin.
  await actor(db,A.driver);
  const chauffeur=await rpc(db,'register_driver',{request_id:key(),name:'Chauffeur TEST',phone:'+221701234567'});assert.equal(chauffeur.statut,'À valider');
  const vehicule=await rpc(db,'save_vehicle',{request_id:key(),parent_id:chauffeur.id,name:'Moto TEST',category:'Moto',registration:'DK-1234-TEST'});
  await admin(db);for(const x of [chauffeur,vehicule])await rpc(db,'admin_review',{request_id:key(),id:x.id,decision:'approve'});
  await actor(db,A.client);await assert.rejects(rpc(db,'quote',{category:'Moto',start:point,end:destination}),'sans tarif publié : pas d’estimation');
  await admin(db);await rpc(db,'set_rate',{request_id:key(),category:'Moto',base_fcfa:300,per_km_fcfa:150,active:true});
  await actor(db,A.driver);await rpc(db,'driver_position',{request_id:key(),position:point,available:true});
  await actor(db,A.client);const devis=await rpc(db,'quote',{category:'Moto',start:point,end:destination});assert.ok(devis.fare_fcfa>=300);
  const proches=await rpc(db,'nearby_drivers',{category:'Moto',start:point});assert.ok(proches.some(d=>d.vehicle_id===vehicule.id),'chauffeur proposé au client');
  const course=await rpc(db,'reserve_ride',{request_id:key(),quote_id:devis.quote_id,vehicle_id:vehicule.id});assert.equal(course.payload.tarif,devis.fare_fcfa);
  await actor(db,A.driver);const acceptee=await suivre(db,course,['Acceptée']);
  await actor(db,A.client);const contacts=await rpc(db,'ride_contacts',{id:course.id});assert.match(contacts.phone||contacts.telephone,/^\+221/);
  await actor(db,A.driver);const terminee=await suivre(db,acceptee,['Chauffeur en route','Course en cours','Terminée']);assert.equal(terminee.statut,'Terminée');
 }finally{await db.close?.();}
});
