import test from 'node:test';import assert from 'node:assert/strict';import fs from 'node:fs';
import {problemesBoutique,bilanBoutique,promotionsEnCours} from '../src/boutique-admin.js';
const r=(kind,statut,payload,extra={})=>({id:kind+statut+(payload.nom||''),kind,statut,payload,publie:['Actif','Disponible','Épuisé'].includes(statut),...extra});
const rows=[
 r('professionnels','Actif',{nom:'Épicerie Diop',telephone:'+221771234567',village:'Koki',localisation:{latitude:15.5,longitude:-15.99}}),
 r('professionnels','Actif',{nom:'Sans tout'}),
 r('boutiques','Actif',{nom:'Boutique du marché',whatsapp:'+221761234567',village:'Koki',photos:['a/b.jpg']}),
 r('boutiques','Actif',{nom:'Dépôt'},{professionnel:{telephone:'+221771234567'}}),
 r('produits','Disponible',{nom:'Riz',prix:4500,ancien_prix:5000,stock:8,description:'Riz parfumé',image_path:'a/c.jpg'}),
 r('produits','Disponible',{nom:'Huile',prix:7500,ancien_prix:10000,stock:2,description:'Huile',photos:['a/d.jpg']}),
 r('produits','Épuisé',{nom:'Sucre',prix:800,stock:0,description:'Sucre'}),
 r('produits','Archivé',{nom:'Ancien'}),
 r('services','Disponible',{nom:'Plomberie',tarif:'devis',description:'Fuites'}),
 r('services','À valider',{nom:'Couture',prix:null,description:''})
];
test('Boutique en ligne : points à corriger pour vendre en ligne',()=>{
 assert.deepEqual(problemesBoutique(rows[0]),[]);
 assert.equal(problemesBoutique(rows[1]).length,3,'téléphone, GPS, village');
 assert.deepEqual(problemesBoutique(rows[2]),[]);
 assert.match(problemesBoutique(rows[3])[0],/téléphone du commerce/);
 assert.deepEqual(problemesBoutique(rows[4]),[]);
 assert.deepEqual(problemesBoutique(rows[6]),['Épuisé : réapprovisionner ou masquer le produit.','Pas de photo : les clients voient seulement un pictogramme.']);
 assert.deepEqual(problemesBoutique(rows[7]),[],'fiche archivée ignorée');
 assert.equal(problemesBoutique(rows[9]).length,2);
 assert.match(problemesBoutique(r('boutiques','Actif',{nom:'X',village:'Koki',photos:['p']}))[0],/Aucun numéro/);
});
test('Boutique en ligne : compteurs et promotions comme dans l’application',()=>{
 const b=bilanBoutique(rows);
 assert.deepEqual([b.produitsEnLigne,b.promotions,b.epuises,b.sansPhoto,b.boutiquesEnLigne,b.servicesEnLigne,b.enAttente,b.aVerifier],[3,2,1,1,2,1,1,4]);
 assert.deepEqual(promotionsEnCours(rows).map(x=>[x.payload.nom,x.remise]),[['Huile',25],['Riz',10]]);
});
test('Boutique en ligne : écran branché, lecture seule',()=>{
 const app=fs.readFileSync(new URL('../src/app.js',import.meta.url),'utf8'),src=fs.readFileSync(new URL('../src/boutique-admin.js',import.meta.url),'utf8');
 assert.match(app,/k==='boutique-en-ligne'/);assert.match(src,/admin_records/);
 assert.doesNotMatch(src,/admin_update|moderate|review_changes|innerHTML/,'aucune écriture depuis cette vue');
});
