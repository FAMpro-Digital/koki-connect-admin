import test from 'node:test';import assert from 'node:assert/strict';import {PGlite} from '@electric-sql/pglite';import {readFile} from 'node:fs/promises';import {randomUUID as key} from 'node:crypto';
import {setupSupabaseStub,setupBusinessDB,fixtureBusiness,actor,rpc,testActors} from './helpers/business-db.js';
import '../src/commerce-contract.js';
const C=globalThis.KokiCommerceContract;
const sql=name=>readFile(new URL('../supabase/'+name,import.meta.url),'utf8');
const before=['schema.sql','proposals/commerce-transport-foundation.sql','proposals/phase2-transactions.sql','proposals/merchant-profiles.sql'];
const open=()=>{const pg=new PGlite();return {pg,db:{query:(q,v)=>v?pg.query(q,v):pg.exec(q).then(x=>x.at(-1))}};};
const rows=async(db,q,v)=>(await db.query(q,v)).rows;
async function legacyDB(db){await setupSupabaseStub(db);for(const f of before)await db.query(await sql(f));for(const id of Object.values(testActors))await db.query('insert into auth.users(id) values($1)',[id]);await db.query("insert into koki_admin_members(user_id,role) values($1,'superadmin'),($2,'editor')",[testActors.admin,testActors.editor]);}
async function photo(db,owner){const path=owner+'/'+key()+'.jpg';await db.query('reset role');await db.query("insert into storage.objects(bucket_id,name) values('koki-media',$1)",[path]);return path;}
async function revisionOf(db,id){await db.query('reset role');return (await rows(db,'select revision from koki_records where id=$1',[id]))[0].revision;}

test('migration compatible avec les données existantes : aucune ligne modifiée, anciens parcours intacts',async()=>{
 const {pg,db}=open();
 try{
  await legacyDB(db);
  // Données créées par les anciennes commandes (avant la migration).
  await actor(db,testActors.merchant);const pro=await rpc(db,'register_professional',{request_id:key(),name:'TEST Ancien commerce',phone:'+999000000002',profile:'Les deux'});
  await actor(db,testActors.provider);const waiting=await rpc(db,'register_professional',{request_id:key(),name:'TEST Prestataire en attente',phone:'+999000000003',profile:'Prestataire de services'});
  await actor(db,testActors.admin,'aal2');await rpc(db,'admin_review',{request_id:key(),id:pro.id,decision:'approve'});
  await actor(db,testActors.merchant);const shop=await rpc(db,'save_shop',{request_id:key(),parent_id:pro.id,name:'TEST Ancienne boutique',address:'TEST Koki'});
  const product=await rpc(db,'save_product',{request_id:key(),parent_id:shop.id,name:'TEST Ancien produit',price:500,stock:3});
  const hidden=await rpc(db,'save_product',{request_id:key(),parent_id:shop.id,name:'TEST Produit masqué',price:100,stock:1});
  const service=await rpc(db,'save_service',{request_id:key(),parent_id:pro.id,name:'TEST Ancien service',price:null});
  await actor(db,testActors.admin,'aal2');await rpc(db,'admin_review',{request_id:key(),id:hidden.id,decision:'suspend'});
  await actor(db,testActors.other);const submitted=await rpc(db,'submit_merchant',{request_id:key(),name:'TEST Fiche soumise',profile:'Commerçant',category:'Alimentation',phone:'+221770000000',address:'TEST Koki marché',location:{latitude:15.56,longitude:-16.21},hours:'Lundi 8h–18h',description:'TEST fiche commerçant existante',photos:[]});
  await db.query('reset role');const snapshot=await rows(db,'select id,kind,statut,payload,revision,owner_id,parent_id from koki_records order by id');
  assert.equal(snapshot.find(r=>r.id===shop.id).statut,'Actif');assert.equal(snapshot.find(r=>r.id===submitted.id).statut,'En attente');
  await db.query(await sql('proposals/commerce-modernisation.sql'));
  assert.deepEqual(await rows(db,'select id,kind,statut,payload,revision,owner_id,parent_id from koki_records order by id'),snapshot,'aucune donnée existante ne change');
  // Le catalogue garde les anciennes clés et les éléments existants.
  await actor(db,null,'aal1','anon');const catalog=await rpc(db,'catalog');
  for(const id of [pro.id,shop.id,product.id,service.id])assert.ok(catalog.some(x=>x.id===id),id);
  assert.ok(!catalog.some(x=>x.id===hidden.id||x.id===waiting.id||x.id===submitted.id));
  const item=catalog.find(x=>x.id===product.id);for(const k of ['id','kind','parent_id','nom','prix','stock'])assert.ok(k in item,k);
  assert.equal(catalog.find(x=>x.id===service.id).tarif,undefined,'pas de tarif inventé pour un ancien service');
  // Les deux parcours d'inscription fonctionnent toujours après migration.
  await actor(db,testActors.client);const legacy=await rpc(db,'register_professional',{request_id:key(),name:'TEST Nouveau prestataire',phone:'+999000000004',profile:'Prestataire de services'});assert.equal(legacy.statut,'À valider');
  await actor(db,testActors.driver);const merchant=await rpc(db,'submit_merchant',{request_id:key(),name:'TEST Nouvelle fiche',profile:'Commerçant',category:'Alimentation',phone:'+221771234567',address:'TEST Koki',location:{latitude:15.56,longitude:-16.21},hours:'Lundi 8h–18h',description:'TEST nouvelle fiche commerçant',photos:[]});assert.equal(merchant.statut,'En attente');
  await actor(db,testActors.admin,'aal2');assert.equal((await rpc(db,'review_merchant',{request_id:key(),id:merchant.id,revision:merchant.revision,decision:'approve'})).statut,'Actif');
  assert.equal((await rpc(db,'admin_review',{request_id:key(),id:legacy.id,decision:'approve'})).statut,'Actif');
 }finally{await pg.close();}
});

test('préflight : des doublons existants bloquent la migration sans rien modifier',async()=>{
 const {pg,db}=open();
 try{
  await legacyDB(db);
  await actor(db,testActors.merchant);const pro=await rpc(db,'register_professional',{request_id:key(),name:'TEST Doublons',phone:'+999000000002',profile:'Commerçant'});
  await actor(db,testActors.admin,'aal2');await rpc(db,'admin_review',{request_id:key(),id:pro.id,decision:'approve'});
  await actor(db,testActors.merchant);const shop=await rpc(db,'save_shop',{request_id:key(),parent_id:pro.id,name:'TEST Boutique'});
  await rpc(db,'save_product',{request_id:key(),parent_id:shop.id,name:'TEST Riz',price:500,stock:1});await rpc(db,'save_product',{request_id:key(),parent_id:shop.id,name:'  test   RIZ ',price:600,stock:1});
  await db.query('reset role');await assert.rejects(db.query(await sql('proposals/commerce-modernisation.sql')),/doublons/);
  await db.query('rollback').catch(()=>{});
  assert.equal((await rows(db,"select to_regclass('public.koki_localites') t"))[0].t,null);
  assert.equal((await rows(db,"select count(*)::int n from koki_records where kind='produits'"))[0].n,2);
 }finally{await pg.close();}
});

test('Commerces & Services : parcours complet, validations et catalogue public',async()=>{
 const {pg,db}=open();
 try{
  await setupBusinessDB(db);const f=await fixtureBusiness(db);
  // Fiche : compléments sans identifiant technique, village de la liste uniquement.
  await actor(db,testActors.merchant);
  await assert.rejects(rpc(db,'save_profile_details',{request_id:key(),revision:await revisionOf(db,f.merchant.id),village:'Paris'}),/inconnu/);
  await actor(db,testActors.merchant);
  const details=await rpc(db,'save_profile_details',{request_id:key(),revision:await revisionOf(db,f.merchant.id),village:'Coki',hours:'Lundi–samedi 8 h–20 h'});
  assert.equal(details.statut,'Actif','changer le village ou les horaires ne renvoie pas en validation');
  await actor(db,testActors.merchant);
  const contact=await rpc(db,'save_profile_details',{request_id:key(),revision:details.revision,whatsapp:'+221771234567'});
  assert.equal(contact.statut,'Actif','la fiche reste en ligne pendant la revalidation');assert.equal(contact.payload.whatsapp,undefined,'nouveau numéro non publié avant validation');
  assert.equal(contact.payload.modification.whatsapp,'+221771234567');
  await actor(db,null,'aal1','anon');assert.ok(!JSON.stringify(await rpc(db,'catalog')).includes('+221771234567'),'nouveau numéro absent du catalogue');
  await actor(db,testActors.merchant);await assert.rejects(rpc(db,'review_changes',{request_id:key(),id:f.merchant.id,revision:contact.revision,decision:'approve'}),/Administration Commerce/);
  await actor(db,testActors.admin,'aal2');const applied=await rpc(db,'review_changes',{request_id:key(),id:f.merchant.id,revision:contact.revision,decision:'approve'});
  assert.equal(applied.payload.whatsapp,'+221771234567');assert.equal(applied.payload.modification,undefined);assert.equal(applied.statut,'Actif');
  // Boutique : parent déduit du compte, créée « À valider » ; produits refusés tant qu'elle n'est pas approuvée.
  await actor(db,testActors.merchant);
  const shop=await rpc(db,'save_shop',{request_id:key(),name:'TEST Boutique moderne',village:'Ouarak',hours:'Tous les jours',whatsapp:'+221771234567',location:{latitude:15.5,longitude:-16.0}});
  assert.equal(shop.statut,'À valider');assert.equal(shop.parent_id,f.merchant.id);
  await assert.rejects(rpc(db,'save_product',{request_id:key(),parent_id:shop.id,name:'TEST Trop tôt',price:100,stock:1}),/validation par l’administration/);
  await actor(db,testActors.merchant);await assert.rejects(rpc(db,'save_product',{request_id:key(),name:'TEST Sans boutique précise',price:100,stock:1}),/Choisissez la boutique/);
  await actor(db,testActors.admin,'aal2');await assert.rejects(rpc(db,'moderate',{request_id:key(),id:shop.id,revision:shop.revision+1,decision:'approve'}),/Révision périmée/);
  const approved=await rpc(db,'moderate',{request_id:key(),id:shop.id,revision:shop.revision,decision:'approve'});assert.equal(approved.statut,'Actif');
  // Produit : ancien prix, plusieurs photos, stock → disponibilité, doublons refusés.
  await actor(db,testActors.merchant);const p1=await photo(db,testActors.merchant),p2=await photo(db,testActors.merchant);await actor(db,testActors.merchant);
  const product=await rpc(db,'save_product',{request_id:key(),parent_id:shop.id,name:'TEST Mil 5 kg',category:'Alimentation',price:2500,old_price:3000,stock:4,photos:[p1,p2]});
  assert.equal(product.statut,'Disponible');assert.deepEqual(product.payload.photos,[p1,p2]);assert.equal(product.payload.image_path,p1);assert.equal(product.payload.ancien_prix,3000);
  await assert.rejects(rpc(db,'save_product',{request_id:key(),parent_id:shop.id,name:'TEST Prix',price:500,old_price:400,stock:1}),/ancien prix/);
  await assert.rejects(rpc(db,'save_product',{request_id:key(),parent_id:shop.id,name:'  test MIL   5 kg ',price:100,stock:1}),/même nom/);
  await assert.rejects(rpc(db,'save_product',{request_id:key(),parent_id:shop.id,name:'TEST Photo volée',price:100,stock:1,photos:[testActors.client+'/'+key()+'.jpg']}),/Photo privée/);
  await assert.rejects(rpc(db,'save_product',{request_id:key(),parent_id:shop.id,name:'TEST Six photos',price:100,stock:1,photos:[1,2,3,4,5,6].map(()=>testActors.merchant+'/'+key()+'.jpg')}),/Cinq photos/);
  const out=await rpc(db,'save_product',{request_id:key(),id:product.id,revision:product.revision,parent_id:shop.id,name:'TEST Mil 5 kg',price:2500,stock:0,photos:[p1,p2]});
  assert.equal(out.statut,'Épuisé');assert.equal(out.payload.ancien_prix,undefined,'ancien prix retiré quand il n’est plus envoyé');
  // Idempotence : même clé = même résultat ; même clé pour une autre requête = refus.
  const same={request_id:key(),parent_id:shop.id,name:'TEST Savon',price:300,stock:5};const s1=await rpc(db,'save_product',same),s2=await rpc(db,'save_product',same);assert.equal(s1.id,s2.id);
  await assert.rejects(rpc(db,'save_product',{...same,name:'TEST Autre'}),/Clé déjà utilisée/);
  // Services : fixe ou sur devis, zone d'intervention.
  await actor(db,testActors.provider);
  const devis=await rpc(db,'save_service',{request_id:key(),name:'TEST Électricité',category:'Électricité',pricing:'devis',zone:'Koki et environs'});assert.equal(devis.payload.tarif,'devis');assert.equal(devis.payload.prix,undefined);
  const fixe=await rpc(db,'save_service',{request_id:key(),name:'TEST Dépannage',category:'Électricité',pricing:'fixe',price:2000});assert.equal(fixe.payload.prix,2000);
  await assert.rejects(rpc(db,'save_service',{request_id:key(),name:'TEST Incohérent',pricing:'devis',price:1000}),/pas de prix/);
  await assert.rejects(rpc(db,'save_service',{request_id:key(),name:'TEST Sans prix',pricing:'fixe'}),/Prix catalogue/);
  // Catalogue public : nouveaux champs, produit épuisé visible, aucun propriétaire ni donnée d'administration.
  await actor(db,null,'aal1','anon');const catalog=await rpc(db,'catalog');
  const c=catalog.find(x=>x.id===product.id);assert.equal(c.statut,'Épuisé');assert.deepEqual(c.photos,[p1,p2]);
  const b=catalog.find(x=>x.id===shop.id);assert.equal(b.village,'Ouarak');assert.equal(b.whatsapp,'+221771234567');
  assert.equal(catalog.find(x=>x.id===devis.id).tarif,'devis');
  // Les chemins de photos commencent par le dossier du compte (règle Storage existante) : seul endroit où il apparaît.
  const text=JSON.stringify(catalog.map(({photos,image_path,...x})=>x));for(const secret of ['owner_id','client_id','moderation','merchant_submission',testActors.merchant,testActors.provider])assert.ok(!text.includes(secret),secret);
  // Photos publiques autorisées pour le produit épuisé, refusées une fois archivé.
  await db.query('reset role');assert.equal((await rows(db,'select koki_private.business_public_image($1) ok',[p1]))[0].ok,true);
  assert.deepEqual((await rows(db,'select nom from koki_localites order by ordre')).map(r=>r.nom),C.localitesParDefaut);
  await actor(db,null,'aal1','anon');assert.equal((await rpc(db,'localites')).length,10);
  await actor(db,testActors.merchant);await rpc(db,'archive',{request_id:key(),id:product.id,revision:await revisionOf(db,product.id)});
  await db.query('reset role');assert.equal((await rows(db,'select koki_private.business_public_image($1) ok',[p1]))[0].ok,false);
  // Après archivage, le nom redevient disponible (l'index ignore les archives).
  await actor(db,testActors.merchant);await rpc(db,'save_product',{request_id:key(),parent_id:shop.id,name:'TEST Mil 5 kg',price:2600,stock:2});
  // Une fiche archivée retire toute sa chaîne du catalogue.
  await actor(db,testActors.admin,'aal2');await rpc(db,'moderate',{request_id:key(),id:f.merchant.id,revision:await revisionOf(db,f.merchant.id),decision:'archive',note:'TEST fermeture définitive'});
  await actor(db,null,'aal1','anon');const after=await rpc(db,'catalog');assert.ok(!after.some(x=>[f.merchant.id,shop.id,f.shop.id].includes(x.id)||x.parent_id===shop.id));
 }finally{await pg.close();}
});

test('permissions : propriétaire seul sur ses fiches, administration Commerce avec MFA, blocage de modération',async()=>{
 const {pg,db}=open();
 try{
  await setupBusinessDB(db);const f=await fixtureBusiness(db);const rev=id=>revisionOf(db,id);
  // Un autre compte ne modifie ni ne masque les offres d'autrui.
  await actor(db,testActors.client);await assert.rejects(rpc(db,'save_product',{request_id:key(),id:f.product.id,revision:await rev(f.product.id),parent_id:f.shop.id,name:'TEST piraté',price:1,stock:1}),/Propriétaire|inaccessible/);
  await actor(db,testActors.client);await assert.rejects(rpc(db,'set_availability',{request_id:key(),id:f.product.id,revision:await rev(f.product.id),status:'Masqué'}),/inaccessible/);
  await actor(db,testActors.provider);await assert.rejects(rpc(db,'archive',{request_id:key(),id:f.product.id,revision:await rev(f.product.id)}),/inaccessible/);
  await actor(db,testActors.client);await assert.rejects(rpc(db,'save_profile_details',{request_id:key(),revision:1,village:'Coki'}),/Fiche professionnelle requise/);
  // Décisions réservées à l'administration Commerce avec double authentification.
  const decide=async(who,aal)=>{await actor(db,who,aal);return rpc(db,'moderate',{request_id:key(),id:f.shop.id,revision:await rev(f.shop.id),decision:'suspend'});};
  await assert.rejects(decide(testActors.merchant,'aal2'),/Administration Commerce/);
  await assert.rejects(decide(testActors.admin,'aal1'),/Administration Commerce/);
  await assert.rejects(decide(testActors.editor,'aal2'),/Administration Commerce/,'un éditeur de contenus ne modère pas les commerces');
  await db.query('reset role');await db.query("insert into koki_admin_members(user_id,role) values($1,'manager')",[testActors.other]);
  assert.equal((await decide(testActors.other,'aal2')).statut,'Fermé','un gestionnaire Commerce peut suspendre');
  await actor(db,null,'aal1','anon');await assert.rejects(rpc(db,'moderate',{request_id:key(),id:f.shop.id,revision:1,decision:'approve'}),/Compte permanent|Administration Commerce/);
  // Boutique suspendue : non modifiable par le propriétaire.
  await actor(db,testActors.merchant);await assert.rejects(rpc(db,'save_shop',{request_id:key(),id:f.shop.id,revision:await rev(f.shop.id),name:'TEST contournement'}),/contactez/);
  // Produit suspendu par l'administration : le propriétaire ne peut pas le remettre en ligne.
  await actor(db,testActors.admin,'aal2');await rpc(db,'moderate',{request_id:key(),id:f.product.id,revision:await rev(f.product.id),decision:'suspend'});
  await actor(db,testActors.merchant);await assert.rejects(rpc(db,'set_availability',{request_id:key(),id:f.product.id,revision:await rev(f.product.id),status:'Disponible'}),/suspendu par l’administration/);
  // Produit d'une boutique suspendue : impossible de le rétablir avant la boutique.
  await actor(db,testActors.admin,'aal2');await assert.rejects(rpc(db,'moderate',{request_id:key(),id:f.product.id,revision:await rev(f.product.id),decision:'approve'}),/parente non approuvée/);
  await actor(db,testActors.admin,'aal2');await rpc(db,'moderate',{request_id:key(),id:f.shop.id,revision:await rev(f.shop.id),decision:'approve'});
  await actor(db,testActors.admin,'aal2');await rpc(db,'moderate',{request_id:key(),id:f.product.id,revision:await rev(f.product.id),decision:'approve'});
  await actor(db,testActors.merchant);assert.equal((await rpc(db,'set_availability',{request_id:key(),id:f.product.id,revision:await rev(f.product.id),status:'Masqué'})).statut,'Masqué');
  // L'ancienne commande admin_review pose aussi le blocage.
  await actor(db,testActors.admin,'aal2');await rpc(db,'admin_review',{request_id:key(),id:f.service.id,decision:'suspend'});
  await actor(db,testActors.provider);await assert.rejects(rpc(db,'set_availability',{request_id:key(),id:f.service.id,revision:await rev(f.service.id),status:'Disponible'}),/suspendu/);
  // Aucun accès direct aux tables ni aux routeurs internes.
  await actor(db,testActors.merchant);await assert.rejects(db.query("update koki_records set statut='Actif' where id=$1",[f.shop.id]));
  await assert.rejects(db.query("select koki_private.merchant_business('catalog','{}')"));
  await assert.rejects(db.query("insert into koki_localites(nom) values('TEST Village pirate')"));
  await actor(db,testActors.admin,'aal2');await db.query("insert into koki_localites(nom,type) values('TEST Nouveau quartier','Quartier')");
  await actor(db,testActors.admin,'aal2');await assert.rejects(db.query("delete from koki_localites where nom='Coki'"));
 }finally{await pg.close();}
});

test('contrat partagé = règles du serveur : chaque transition autorisée ou refusée à l’identique',async()=>{
 const {pg,db}=open();
 try{
  await setupBusinessDB(db);const f=await fixtureBusiness(db);
  const target={professionnels:f.provider.id,boutiques:f.shop.id,produits:f.product.id,services:f.service.id};
  for(const kind of Object.keys(C.decisions))for(const statut of C.statuts[kind])for(const decision of ['approve','reject','suspend','archive']){
   await db.query('reset role');await db.query("update koki_records set statut='Actif' where id in ($1,$2,$3) and id<>$4",[f.merchant.id,f.shop.id,f.provider.id,target[kind]]);await db.query("update koki_records set statut=$1,payload=payload||jsonb_build_object('moderation',jsonb_build_object('decision','reject','note','TEST préparation du statut','at',clock_timestamp())) where id=$2",[statut,target[kind]]);
   const revision=await revisionOf(db,target[kind]);await actor(db,testActors.admin,'aal2');
   const expected=C.transition(kind,statut,decision);
   const result=await db.query('select public.koki_business($1,$2::jsonb) r',['moderate',JSON.stringify({request_id:key(),id:target[kind],revision,decision,...(decision==='reject'?{note:'TEST motif du refus'}:{})})]).then(x=>x.rows[0].r.statut,e=>e.message);
   assert.equal(expected?result:/incompatible/.test(result)?null:result,expected,`${kind} ${statut} ${decision}`);
  }
 }finally{await pg.close();}
});

test('fiche unifiée save_profile : GPS facultatif, statuts, revalidation et garde-fous',async()=>{
 const {pg,db}=open();
 try{
  await setupBusinessDB(db);const f=await fixtureBusiness(db);const rev=id=>revisionOf(db,id);
  const base={name:'TEST Atelier Fall',profile:'Les deux',category:'Couture',phone:'77 123 45 67',village:'Coki'};
  await actor(db,testActors.client);await assert.rejects(rpc(db,'save_profile',{request_id:key(),...base}),/Numéro de téléphone invalide/,'le serveur exige le format international');
  await actor(db,testActors.client);await assert.rejects(rpc(db,'save_profile',{request_id:key(),...base,phone:'+221771234567',village:'Dakar'}),/inconnu/);
  await actor(db,testActors.client);await assert.rejects(rpc(db,'save_profile',{request_id:key(),...base,phone:'+221771234567',village:''}),/village/);
  await actor(db,testActors.client);const created=await rpc(db,'save_profile',{request_id:key(),...base,phone:'+221771234567'});
  assert.equal(created.statut,'En attente');assert.equal(created.payload.localisation,undefined,'aucune position exigée');assert.equal(created.owner_id,testActors.client);
  await actor(db,testActors.client);await assert.rejects(rpc(db,'save_profile',{request_id:key(),...base,phone:'+221771234567'}),/déjà créée/);
  await actor(db,testActors.client);await assert.rejects(rpc(db,'save_shop',{request_id:key(),name:'TEST Trop tôt'}),/non approuvée/);
  await actor(db,testActors.other);await assert.rejects(rpc(db,'save_profile',{request_id:key(),...base,phone:'+221771234567',id:created.id,revision:created.revision}),/inaccessible/);
  await actor(db,testActors.admin,'aal2');const approved=await rpc(db,'moderate',{request_id:key(),id:created.id,revision:created.revision,decision:'approve'});assert.equal(approved.statut,'Actif');
  // Modifier horaires, village ou GPS : reste en ligne. Modifier le nom ou le WhatsApp : nouvelle validation.
  await actor(db,testActors.client);const minor=await rpc(db,'save_profile',{request_id:key(),...base,phone:'+221771234567',id:created.id,revision:approved.revision,village:'Pallene',hours:'Lundi–samedi',location:{latitude:15.51,longitude:-15.99}});
  assert.equal(minor.statut,'Actif');assert.equal(minor.payload.localisation.latitude,15.51);
  await actor(db,testActors.client);const major=await rpc(db,'save_profile',{request_id:key(),...base,phone:'+221771234567',id:created.id,revision:minor.revision,village:'Pallene',whatsapp:'+221761234567'});
  assert.equal(major.statut,'Actif','version approuvée conservée en ligne');assert.equal(major.payload.localisation,undefined,'GPS retiré quand il n’est plus envoyé');
  assert.equal(major.payload.whatsapp,undefined);assert.equal(major.payload.modification.whatsapp,'+221761234567');
  await actor(db,testActors.client);const renamed=await rpc(db,'save_profile',{request_id:key(),...base,phone:'+221771234567',id:created.id,revision:major.revision,village:'Pallene',whatsapp:'+221761234567',name:'TEST Nouveau nom secret'});
  assert.equal(renamed.payload.nom,'TEST Atelier Fall');assert.equal(renamed.payload.modification.nom,'TEST Nouveau nom secret');
  await actor(db,null,'aal1','anon');const cat=JSON.stringify(await rpc(db,'catalog'));assert.ok(cat.includes('TEST Atelier Fall')&&!cat.includes('Nouveau nom secret')&&!cat.includes('+221761234567'),'catalogue : ancienne version seulement');
  await actor(db,testActors.admin,'aal2');const refusedChanges=await rpc(db,'review_changes',{request_id:key(),id:created.id,revision:renamed.revision,decision:'reject',note:'TEST nom à préciser'});
  assert.equal(refusedChanges.statut,'Actif');assert.equal(refusedChanges.payload.nom,'TEST Atelier Fall');assert.equal(refusedChanges.payload.modification,undefined);assert.equal(refusedChanges.payload.moderation.note,'TEST nom à préciser');
  await actor(db,testActors.admin,'aal2');await assert.rejects(rpc(db,'review_changes',{request_id:key(),id:created.id,revision:refusedChanges.revision,decision:'approve'}),/Aucune modification/);
  // Revenir aux valeurs approuvées supprime la modification en attente.
  await actor(db,testActors.client);const pending=await rpc(db,'save_profile',{request_id:key(),...base,phone:'+221771234567',id:created.id,revision:refusedChanges.revision,village:'Pallene',name:'TEST Autre nom'});assert.ok(pending.payload.modification);
  await actor(db,testActors.client);const reverted=await rpc(db,'save_profile',{request_id:key(),...base,phone:'+221771234567',id:created.id,revision:pending.revision,village:'Pallene'});assert.equal(reverted.payload.modification,undefined);
  // Fiche refusée (avant toute mise en ligne) puis corrigée : nouvelle validation.
  await actor(db,testActors.other);const second=await rpc(db,'save_profile',{request_id:key(),...base,name:'TEST Second atelier',phone:'+221781234567'});
  await actor(db,testActors.admin,'aal2');const refused=await rpc(db,'moderate',{request_id:key(),id:second.id,revision:second.revision,decision:'reject',note:'TEST photo manquante'});assert.equal(refused.statut,'Refusé');
  await actor(db,testActors.other);const fixed=await rpc(db,'save_profile',{request_id:key(),...base,phone:'+221781234567',id:second.id,revision:refused.revision,name:'TEST Second atelier corrigé'});assert.equal(fixed.statut,'En attente');assert.equal(fixed.payload.nom,'TEST Second atelier corrigé');
  // Retirer une activité qui a encore des offres est refusé (fiche du prestataire de la fixture).
  await actor(db,testActors.provider);await assert.rejects(rpc(db,'save_profile',{request_id:key(),id:f.provider.id,revision:await rev(f.provider.id),name:'TEST Prestataire',profile:'Commerçant',category:'Plomberie',phone:'+999000000003',village:'Coki'}),/Archivez vos services/);
  // Une fiche suspendue n'est pas modifiable par son propriétaire.
  await actor(db,testActors.admin,'aal2');await rpc(db,'moderate',{request_id:key(),id:f.merchant.id,revision:await rev(f.merchant.id),decision:'suspend'});
  await actor(db,testActors.merchant);await assert.rejects(rpc(db,'save_profile',{request_id:key(),id:f.merchant.id,revision:await rev(f.merchant.id),name:'TEST',profile:'Commerçant',category:'X',phone:'+999000000002',village:'Coki'}),/administration/);
 }finally{await pg.close();}
});

test('photos : dossier anonyme, aucun identifiant de compte dans le catalogue, dossiers d’autrui interdits',async()=>{
 const {pg,db}=open();
 try{
  await setupBusinessDB(db);const f=await fixtureBusiness(db);
  await actor(db,testActors.merchant);const {folder}=await rpc(db,'media_folder');assert.match(folder,/^[0-9a-f-]{36}$/);assert.notEqual(folder,testActors.merchant);
  await actor(db,testActors.merchant);assert.equal((await rpc(db,'media_folder')).folder,folder,'dossier stable');
  await actor(db,null,'aal1','anon');await assert.rejects(rpc(db,'media_folder'),/Compte permanent/);
  // Dépôt autorisé dans son dossier anonyme ; refusé dans le dossier d'un autre compte.
  const path=folder+'/'+key()+'.webp';await actor(db,testActors.merchant);await db.query("insert into storage.objects(bucket_id,name) values('koki-media',$1)",[path]);
  await actor(db,testActors.client);await assert.rejects(db.query("insert into storage.objects(bucket_id,name) values('koki-media',$1)",[folder+'/'+key()+'.jpg']));
  await actor(db,testActors.client);assert.equal((await rows(db,'select name from storage.objects where name=$1',[path])).length,0,'photo non publiée invisible');
  await actor(db,testActors.merchant);const product=await rpc(db,'save_product',{request_id:key(),parent_id:f.shop.id,name:'TEST Produit photo',price:100,stock:1,photos:[path]});
  await actor(db,testActors.client);await assert.rejects(rpc(db,'save_product',{request_id:key(),parent_id:f.shop.id,name:'TEST Vol',price:1,stock:1,photos:[path]}),/Propriétaire|Photo privée/);
  await actor(db,null,'aal1','anon');const catalog=await rpc(db,'catalog');const text=JSON.stringify(catalog);
  assert.ok(catalog.find(x=>x.id===product.id).photos.includes(path));for(const id of Object.values(testActors))assert.ok(!text.includes(id),'identifiant de compte absent : '+id);
  await actor(db,null,'aal1','anon');assert.equal((await rows(db,'select name from storage.objects where name=$1',[path])).length,1,'photo publiée lisible');
  await actor(db,testActors.client);await assert.rejects(db.query('delete from storage.objects where name=$1 returning name',[path]).then(r=>{if(!r.rows.length)throw Error('refusé');}));
  // Photo d'une modification en attente : propriétaire et administration seulement, jamais le public.
  const pendingPath=folder+'/'+key()+'.jpg';await actor(db,testActors.merchant);await db.query("insert into storage.objects(bucket_id,name) values('koki-media',$1)",[pendingPath]);
  await actor(db,testActors.merchant);const changed=await rpc(db,'save_profile',{request_id:key(),id:f.merchant.id,revision:await revisionOf(db,f.merchant.id),name:'TEST Boutique',profile:'Commerçant',category:'Alimentation',phone:'+999000000002',village:'Coki',photos:[pendingPath]});
  assert.equal(changed.statut,'Actif');assert.deepEqual(changed.payload.modification.photos,[pendingPath]);
  await actor(db,null,'aal1','anon');assert.equal((await rows(db,'select name from storage.objects where name=$1',[pendingPath])).length,0,'photo en attente invisible du public');
  await actor(db,null,'aal1','anon');assert.ok(!JSON.stringify(await rpc(db,'catalog')).includes(pendingPath));
  await actor(db,testActors.admin,'aal2');assert.equal((await rows(db,'select name from storage.objects where name=$1',[pendingPath])).length,1,'visible pour la validation');
  await actor(db,testActors.merchant);assert.equal((await rows(db,'delete from storage.objects where name=$1 returning name',[pendingPath])).length,0,'photo en attente protégée contre la suppression');
  await actor(db,testActors.admin,'aal2');await rpc(db,'review_changes',{request_id:key(),id:f.merchant.id,revision:changed.revision,decision:'approve'});
  await actor(db,null,'aal1','anon');assert.equal((await rows(db,'select name from storage.objects where name=$1',[pendingPath])).length,1,'publiée après validation');
 }finally{await pg.close();}
});
