import test from 'node:test';import assert from 'node:assert/strict';import fs from 'node:fs';import {createHash} from 'node:crypto';import '../src/commerce-contract.js';
const C=globalThis.KokiCommerceContract,FICHIER=new URL('../src/commerce-contract.js',import.meta.url);
// Empreinte du contrat : identique dans les deux dépôts. Après toute modification, copier le fichier
// dans l'autre dépôt et mettre à jour cette empreinte des deux côtés.
const EMPREINTE='e79c261cb12e481eadf88424468e521ad842a77aa787f86fa7a42e8653886156';
test('contrat Commerces & Services : identique dans les deux dépôts',()=>{assert.equal(createHash('sha256').update(fs.readFileSync(FICHIER)).digest('hex'),EMPREINTE);});
test('numéros sénégalais normalisés, liens appel et WhatsApp',()=>{
 for(const [entree,attendu] of [['77 123 45 67','+221771234567'],['771234567','+221771234567'],['+221 77-123-45-67','+221771234567'],['00221771234567','+221771234567'],['221 33 961 23 45','+221339612345'],['(76) 123.45.67','+221761234567'],['+33 6 12 34 56 78','+33612345678'],['+221 12 345 67 89',null],['17',null],['12345',null],['',null],[null,null],['abc',null]])assert.equal(C.normaliserTelephone(entree),attendu,String(entree));
 assert.equal(C.afficherTelephone('771234567'),'+221 77 123 45 67');assert.equal(C.lienAppel('77 123 45 67'),'tel:+221771234567');assert.equal(C.lienAppel('17'),null);
 assert.equal(C.lienWhatsApp('77 123 45 67'),'https://wa.me/221771234567');assert.equal(C.lienWhatsApp('bonjour'),null);
});
test('commande WhatsApp préremplie avec le produit et son prix',()=>{
 const m=C.messageCommande({produit:'Riz 25 kg',prix:12500,boutique:'Boutique Fall',quantite:2});
 assert.ok(m.startsWith('Bonjour Boutique Fall'));assert.ok(m.includes('Riz 25 kg × 2'));assert.ok(m.includes('12 500 FCFA'));
 const url=C.lienCommandeWhatsApp('+221771234567',{produit:'Huile & savon',prix:1000});assert.ok(url.startsWith('https://wa.me/221771234567?text='));assert.ok(decodeURIComponent(url.split('text=')[1]).includes('Huile & savon × 1 — 1 000 FCFA'));assert.ok(!url.split('text=')[1].includes('&'));
});
test('prix, tarifs, doublons et contrôles de formulaire',()=>{
 assert.equal(C.formaterPrix(1250000),'1 250 000 FCFA');assert.equal(C.formaterPrix(-1),'');assert.equal(C.formaterPrix(1.5),'');
 assert.equal(C.libellePrix({tarif:'devis'}),'Sur devis');assert.equal(C.libellePrix({tarif:'fixe',prix:3000}),'3 000 FCFA');
 assert.equal(C.cleNom('  Riz   PARFUMÉ '),'riz parfumé');
 assert.deepEqual(C.verifierOffre('produits',{nom:'Riz',prix:500,ancien_prix:600,stock:3,photos:['a','b']}),[]);
 assert.equal(C.verifierOffre('produits',{nom:'Riz',prix:500,ancien_prix:400,stock:3}).length,1);
 assert.equal(C.verifierOffre('produits',{nom:'',prix:1.5,stock:-1}).length,3);
 assert.equal(C.verifierOffre('services',{nom:'Plomberie',tarif:'devis',prix:100}).length,1);assert.deepEqual(C.verifierOffre('services',{nom:'Plomberie',tarif:'fixe',prix:100}),[]);
 assert.equal(C.verifierOffre('produits',{nom:'Riz',prix:1,stock:1,photos:['a','a']}).length,1);assert.equal(C.verifierOffre('boutiques',{nom:'B',whatsapp:'123'}).length,1);
});
test('statuts : validation, publication et décisions cohérentes',()=>{
 for(const kind of Object.keys(C.decisions))for(const [d,{from,to}] of Object.entries(C.decisions[kind])){assert.ok(C.statuts[kind].includes(to),kind+d);for(const s of from)assert.ok(C.statuts[kind].includes(s),kind+s);}
 assert.equal(C.transition('boutiques','À valider','approve'),'Actif');assert.equal(C.transition('produits','Disponible','reject'),null);
 assert.deepEqual(C.decisionsPossibles('professionnels','En attente'),['approve','reject','archive']);
 assert.ok(C.estPublic('produits','Épuisé'));assert.ok(!C.estPublic('boutiques','À valider'));assert.equal(C.localitesParDefaut.length,10);
 assert.equal(C.parents.produits,'boutiques');assert.ok(Object.isFrozen(C));
});

test('revalidation : comparaison publiée / proposée, seul le champ modifié est signalé',()=>{
 const payload={nom:'Épicerie Diop',type:'Commerçant',telephone:'+221771234567',photos:['a/1.jpg'],modification:{nom:'Épicerie Diop & Fils',type:'Commerçant',telephone:'+221771234567',photos:['a/1.jpg','a/2.jpg'],soumis_le:'2026-10-11T00:00:00Z'}};
 const d=C.comparerModification(payload);assert.deepEqual(d.map(x=>x.champ),['nom','type','telephone','whatsapp','photos']);
 assert.deepEqual(d.filter(x=>x.modifie).map(x=>x.champ),['nom','photos']);assert.equal(d[0].avant,'Épicerie Diop');assert.equal(d[0].apres,'Épicerie Diop & Fils');
 assert.deepEqual(C.comparerModification({nom:'X'}),[]);assert.equal(C.libellesDemande.modification,'Modification d’une fiche en ligne');
});
