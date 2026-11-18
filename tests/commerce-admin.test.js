import test from 'node:test';import assert from 'node:assert/strict';import {PGlite} from '@electric-sql/pglite';import {randomUUID as key} from 'node:crypto';
import {setupBusinessDB,fixtureBusiness,actor,rpc,testActors} from './helpers/business-db.js';
const open=()=>{const pg=new PGlite();return {pg,db:{query:(q,v)=>v?pg.query(q,v):pg.exec(q).then(x=>x.at(-1))}};};
const rev=async(db,id)=>{await db.query('reset role');return (await db.query('select revision from koki_records where id=$1',[id])).rows[0].revision;};
async function world(){const {pg,db}=open();await setupBusinessDB(db);const f=await fixtureBusiness(db);
 await db.query('reset role');await db.query("insert into koki_admin_members(user_id,role) values($1,'analyst')",[testActors.other]);
 // Une inscription en attente (client), une boutique à valider, une modification de fiche en ligne.
 await actor(db,testActors.client);const pending=await rpc(db,'save_profile',{request_id:key(),name:'TEST Atelier en attente',profile:'Les deux',category:'Couture',phone:'+221771234567',village:'Coki'});
 await actor(db,testActors.merchant);const shop2=await rpc(db,'save_shop',{request_id:key(),name:'TEST Annexe',village:'Ouarak'});
 await actor(db,testActors.provider);const modif=await rpc(db,'save_profile',{request_id:key(),id:f.provider.id,revision:await rev(db,f.provider.id),name:'TEST Prestataire renommé',profile:'Prestataire de services',category:'Plomberie',phone:'+999000000003',village:'Coki'});
 return {pg,db,f,pending,shop2,modif};}

test('statistiques réelles : comptages exacts, lecture avec MFA, refus sinon',async()=>{
 const {pg,db}=await world();
 try{
  await actor(db,testActors.other,'aal2');const s=await rpc(db,'admin_stats');
  await db.query('reset role');const count=async q=>(await db.query(q)).rows[0].n;
  assert.equal(s.professionnels_inscrits,await count("select count(*)::int n from koki_records where kind='professionnels'"));
  assert.equal(s.inscriptions_en_attente,1);assert.equal(s.boutiques_en_attente,1);assert.equal(s.modifications_en_attente,1);
  assert.equal(s.boutiques_actives,1);assert.equal(s.produits_publies,1);assert.equal(s.services_disponibles,1);assert.equal(s.archives,0);assert.equal(s.suspendus,0);
  for(const [who,aal,role] of [[testActors.other,'aal1'],[testActors.client,'aal2'],[null,'aal1','anon']]){await actor(db,who,aal,role);await assert.rejects(rpc(db,'admin_stats'),/MFA|Compte/);}
  // Les chiffres suivent les décisions réelles.
  await actor(db,testActors.admin,'aal2');const prod=(await db.query("select id from koki_records where kind='produits'")).rows[0].id;
  await actor(db,testActors.admin,'aal2');await rpc(db,'moderate',{request_id:key(),id:prod,revision:await rev(db,prod),decision:'archive',note:'TEST doublon'});
  await actor(db,testActors.admin,'aal2');const after=await rpc(db,'admin_stats');assert.equal(after.produits_publies,0);assert.equal(after.archives,1);
 }finally{await pg.close();}
});
test('file de validation : inscriptions, boutiques et modifications, sans identifiant de compte',async()=>{
 const {pg,db,pending,shop2,modif}=await world();
 try{
  await actor(db,testActors.other,'aal2');await assert.rejects(rpc(db,'admin_queue'),/Administration Commerce/,'un analyste ne valide pas');
  await actor(db,testActors.admin,'aal2');const q=await rpc(db,'admin_queue');
  assert.deepEqual(q.map(x=>x.demande).sort(),['boutique','inscription','modification']);
  const m=q.find(x=>x.demande==='modification');assert.equal(m.id,modif.id);assert.equal(m.payload.nom,'TEST Prestataire');assert.equal(m.payload.modification.nom,'TEST Prestataire renommé');
  const b=q.find(x=>x.demande==='boutique');assert.equal(b.id,shop2.id);assert.equal(b.parent.nom,'TEST Boutique');assert.equal(b.parent.statut,'Actif');
  const text=JSON.stringify(q);for(const id of Object.values(testActors))assert.ok(!text.includes(id),id);assert.ok(!text.includes('owner_id'));
  // Décision avec motif : historique conservé dans le journal.
  await actor(db,testActors.admin,'aal2');await rpc(db,'review_changes',{request_id:key(),id:modif.id,revision:modif.revision,decision:'reject',note:'TEST nom trompeur'});
  await actor(db,testActors.admin,'aal2');await rpc(db,'moderate',{request_id:key(),id:pending.id,revision:pending.revision,decision:'approve'});
  await actor(db,testActors.admin,'aal2');const rest=await rpc(db,'admin_queue');assert.deepEqual(rest.map(x=>x.demande),['boutique']);
  await actor(db,testActors.admin,'aal2');const view=(await rpc(db,'admin_records',{kind:'professionnels',query:'prestataire'})).rows[0];
  assert.equal(view.decisions[0].decision,'reject_changes');assert.equal(view.decisions[0].note,'TEST nom trompeur');assert.equal(view.payload.nom,'TEST Prestataire');
  await db.query('reset role');const audit=(await db.query("select actor_id::text a,details from koki_audit where operation='DECISION' and record_id in ($1,$2) order by id",[modif.id,pending.id])).rows;
  const last=audit.slice(-2);assert.equal(last[0].a,testActors.admin);assert.equal(last[0].details.decision,'reject_changes');assert.equal(last[1].details.avant,'En attente');assert.equal(last[1].details.apres,'Actif');
 }finally{await pg.close();}
});
test('aucun auto-validation, chaîne parente exigée, MFA et rôle exigés',async()=>{
 const {pg,db,f,shop2}=await world();
 try{
  // L'administrateur possède aussi une fiche professionnelle : il ne peut ni la valider ni la corriger.
  await actor(db,testActors.admin,'aal2');const own=await rpc(db,'save_profile',{request_id:key(),name:'TEST Fiche de l’admin',profile:'Commerçant',category:'Alimentation',phone:'+221701234567',village:'Coki'});
  for(const [command,input] of [['moderate',{decision:'approve'}],['admin_review',{decision:'approve'}],['admin_update',{name:'TEST'}]]){await actor(db,testActors.admin,'aal2');await assert.rejects(rpc(db,command,{request_id:key(),id:own.id,revision:own.revision,...input}),/propres fiches/,command);}
  await actor(db,testActors.admin,'aal1');await assert.rejects(rpc(db,'moderate',{request_id:key(),id:shop2.id,revision:shop2.revision,decision:'approve'}),/MFA/);
  await actor(db,testActors.other,'aal2');await assert.rejects(rpc(db,'admin_records',{kind:'boutiques'}),/Administration Commerce/);
  await actor(db,testActors.editor,'aal2');await assert.rejects(rpc(db,'review_changes',{request_id:key(),id:f.provider.id,revision:1,decision:'approve'}),/Administration Commerce/);
  // Boutique d'une fiche suspendue : approbation refusée.
  await actor(db,testActors.admin,'aal2');await rpc(db,'moderate',{request_id:key(),id:f.merchant.id,revision:await rev(db,f.merchant.id),decision:'suspend'});
  await actor(db,testActors.admin,'aal2');await assert.rejects(rpc(db,'moderate',{request_id:key(),id:shop2.id,revision:await rev(db,shop2.id),decision:'approve'}),/parente non approuvée/);
  await actor(db,testActors.admin,'aal2');await assert.rejects(rpc(db,'admin_review',{request_id:key(),id:shop2.id,decision:'approve'}),/parente non approuvée/,'ancienne commande aussi');
 }finally{await pg.close();}
});
test('liste et correction des fiches : recherche, filtres, parent choisi dans la liste du même professionnel',async()=>{
 const {pg,db,f,shop2}=await world();
 try{
  await actor(db,testActors.admin,'aal2');const all=await rpc(db,'admin_records',{kind:'produits'});assert.equal(all.total,1);assert.equal(all.rows[0].parent.nom,'TEST Shop');assert.equal(all.rows[0].professionnel.nom,'TEST Boutique');assert.equal(all.rows[0].publie,true);
  await actor(db,testActors.admin,'aal2');assert.equal((await rpc(db,'admin_records',{kind:'boutiques',statut:'À valider'})).total,1);
  await actor(db,testActors.admin,'aal2');assert.equal((await rpc(db,'admin_records',{kind:'boutiques',village:'Ouarak'})).rows[0].payload.nom,'TEST Annexe');
  await actor(db,testActors.admin,'aal2');assert.equal((await rpc(db,'admin_records',{kind:'professionnels',statut:'Modification en attente'})).total,1);
  await actor(db,testActors.admin,'aal2');assert.equal((await rpc(db,'admin_records',{kind:'produits',query:'introuvable'})).total,0);
  await actor(db,testActors.admin,'aal2');await assert.rejects(rpc(db,'admin_records',{kind:'commandes'}),/Rubrique invalide/);
  // Filtre par boutique choisie dans la liste.
  await actor(db,testActors.admin,'aal2');assert.equal((await rpc(db,'admin_records',{kind:'produits',parent_id:shop2.id})).total,0);
  await actor(db,testActors.admin,'aal2');assert.equal((await rpc(db,'admin_records',{kind:'produits',parent_id:f.shop.id})).total,1);
  // Correction : prix, ancien prix, stock (0 → Épuisé) ; le rattachement reste immuable.
  await actor(db,testActors.admin,'aal2');const fixed=await rpc(db,'admin_update',{request_id:key(),id:f.product.id,revision:await rev(db,f.product.id),price:450,old_price:500,stock:0});
  assert.equal(fixed.payload.prix,450);assert.equal(fixed.payload.ancien_prix,500);assert.equal(fixed.statut,'Épuisé');assert.equal(fixed.parent.nom,'TEST Shop');assert.equal(fixed.decisions[0].decision,'correction');
  await actor(db,testActors.admin,'aal2');await assert.rejects(rpc(db,'admin_update',{request_id:key(),id:f.product.id,revision:await rev(db,f.product.id),parent_id:shop2.id}),/Champs inconnus/);
  await actor(db,testActors.admin,'aal2');await assert.rejects(rpc(db,'admin_update',{request_id:key(),id:f.product.id,revision:await rev(db,f.product.id),old_price:100}),/ancien prix/);
  await actor(db,testActors.admin,'aal2');await assert.rejects(rpc(db,'admin_update',{request_id:key(),id:f.product.id,revision:await rev(db,f.product.id),photos:[testActors.client+'/'+key()+'.jpg']}),/photos existantes/);
  await actor(db,testActors.admin,'aal2');await assert.rejects(rpc(db,'admin_update',{request_id:key(),id:f.product.id,revision:1,price:1}),/périmée/);
  await actor(db,testActors.admin,'aal2');const svc=await rpc(db,'admin_update',{request_id:key(),id:f.service.id,revision:await rev(db,f.service.id),pricing:'fixe',price:2500,zone:'Koki'});assert.equal(svc.payload.tarif,'fixe');assert.equal(svc.payload.prix,2500);
  await actor(db,testActors.merchant);await assert.rejects(rpc(db,'admin_update',{request_id:key(),id:f.product.id,revision:await rev(db,f.product.id),price:1}),/Administration Commerce/);
 }finally{await pg.close();}
});
test('ancien formulaire commerçant : revalidation sans retrait, version approuvée conservée',async()=>{
 const {pg,db}=open();
 try{
  await setupBusinessDB(db);const base={name:'TEST Commerce',profile:'Commerçant',category:'Alimentation',phone:'+221770000000',address:'TEST Koki marché',location:{latitude:15.56,longitude:-16.21},hours:'Lundi 8h–18h',description:'TEST fiche commerçant historique',photos:[]};
  await actor(db,testActors.merchant);const saved=await rpc(db,'submit_merchant',{request_id:key(),...base});
  await actor(db,testActors.admin,'aal2');const ok=await rpc(db,'review_merchant',{request_id:key(),id:saved.id,revision:saved.revision,decision:'approve'});
  await actor(db,testActors.merchant);const edit=await rpc(db,'submit_merchant',{request_id:key(),...base,id:saved.id,revision:ok.revision,name:'TEST Commerce renommé',hours:'Tous les jours'});
  assert.equal(edit.statut,'Actif');assert.equal(edit.payload.nom,'TEST Commerce');assert.equal(edit.payload.horaires,'Tous les jours','champs non sensibles appliqués');assert.equal(edit.payload.modification.nom,'TEST Commerce renommé');
  await actor(db,null,'aal1','anon');const cat=await rpc(db,'catalog');assert.equal(cat.length,1);assert.equal(cat[0].nom,'TEST Commerce');
  await actor(db,testActors.admin,'aal2');const applied=await rpc(db,'review_changes',{request_id:key(),id:saved.id,revision:edit.revision,decision:'approve'});assert.equal(applied.payload.nom,'TEST Commerce renommé');
  await actor(db,null,'aal1','anon');assert.equal((await rpc(db,'catalog'))[0].nom,'TEST Commerce renommé');
 }finally{await pg.close();}
});
