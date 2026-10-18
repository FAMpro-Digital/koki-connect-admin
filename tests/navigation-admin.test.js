// Menu de l'administration en accordéon : sous-rubriques de chaque rubrique, alignées sur le tableau de bord.
import test from 'node:test';import assert from 'node:assert/strict';import fs from 'node:fs';
import '../src/rubriques-contract.js';
import {sousEntrees,rubriqueCourante,lireOuvertes,ecrireOuvertes} from '../src/navigation-admin.js';
const R=globalThis.KokiRubriquesContract,r=cle=>R.rubriques.find(x=>x.cle===cle);
const libelles=cle=>sousEntrees(R,r(cle)).map(e=>e.libelle);
test('chaque rubrique s’ouvre sur ses vraies sous-rubriques',()=>{
 assert.deepEqual(libelles('transport'),['🪪 Renseignements','Courses','Chauffeurs','Véhicules','Tarifs Transport','Signalements','📞 Numéros utiles']);
 assert.deepEqual(libelles('sports'),['🪪 Renseignements','Matchs et résultats','Équipes / ASC','📰 Publications','📍 Lieux de la carte']);
 assert.deepEqual(libelles('opportunites'),['🪪 Renseignements','Offres et opportunités','💼 Emplois','🤝 Stages','🎓 Formations','🏆 Concours','📚 Bourses','🌱 Financements']);
 assert.deepEqual(libelles('sante'),['🪪 Renseignements','Structures de santé','📞 Numéros utiles']);
 assert.deepEqual(libelles('services_publics'),['🪪 Renseignements','Annuaire des services','Guides des démarches','Avis officiels','📍 Lieux de la carte','📞 Numéros utiles']);
 assert.deepEqual(libelles('evenements'),['🪪 Renseignements','Agenda des événements']);
 // Renseignements, numéros et lieux propres à chaque rubrique (filtre = rubrique).
 const e=cle=>sousEntrees(R,r(cle));assert.deepEqual(e('sante').find(x=>x.cle==='numeros').query,'sante');assert.deepEqual(e('education').find(x=>x.cle==='lieux').query,'Éducation');
 assert.equal(rubriqueCourante(R,'renseignements','evenements').cle,'evenements');assert.equal(rubriqueCourante(R,'numeros','transport').cle,'transport');
 for(const x of R.rubriques)assert.ok(sousEntrees(R,x).length>0,x.nom);
 const emplois=sousEntrees(R,r('opportunites')).find(e=>e.libelle==='💼 Emplois');assert.deepEqual([emplois.cle,emplois.query],['offres','Emplois']);
});
test('rubrique courante : la bonne rubrique reste ouverte, y compris pour un écran filtré',()=>{
 assert.equal(rubriqueCourante(R,'signalements').cle,'transport');assert.equal(rubriqueCourante(R,'offres','Stages').cle,'opportunites');
 assert.equal(rubriqueCourante(R,'lieux','Services publics').cle,'services_publics');assert.equal(rubriqueCourante(R,'demarches').cle,'services_publics');assert.equal(rubriqueCourante(R,'sport-equipes').cle,'sports');
 assert.equal(rubriqueCourante(R,'evenements').cle,'evenements');
 assert.equal(rubriqueCourante(R,'dashboard'),null);
});
test('rubriques ouvertes mémorisées sur l’appareil, stockage indisponible toléré',()=>{
 const m=new Map(),s={getItem:k=>m.get(k)??null,setItem:(k,v)=>m.set(k,v)};
 ecrireOuvertes(new Set(['transport','sports']),s);assert.deepEqual([...lireOuvertes(s)],['transport','sports']);
 assert.deepEqual([...lireOuvertes({getItem:()=>{throw Error('bloqué');}})],[]);
 assert.deepEqual([...lireOuvertes({getItem:()=>'{"x":1}'})],[]);
});
test('menu, page Rubriques et tableau de bord utilisent la même liste',()=>{
 const app=fs.readFileSync(new URL('../src/app.js',import.meta.url),'utf8'),nav=fs.readFileSync(new URL('../src/navigation-admin.js',import.meta.url),'utf8');
 assert.match(app,/menuRubriques\(side,R,\{n,button,navigate,current,query:currentQuery\}\)/);
 assert.match(app,/rubs\.append\(n\('h2','🧭 Rubriques de l’application'\),cartesRubriques\(R,\{n,button,navigate\}\)\)/);
 assert.match(app,/function renderRubriques\(main\)\{main\.append\(n\('p',[^)]*\),cartesRubriques\(R,\{n,button,navigate\}\)/);
 assert.match(nav,/tete\.setAttribute\('aria-expanded',String\(ouvert\)\);tete\.setAttribute\('aria-controls',id\);/);assert.doesNotMatch(nav,/innerHTML/);
});

test('retour interne : filtres conservés, actualisation sans doublon, accueil de secours',async()=>{
 const {createNavigationTrail}=await import('../src/navigation-admin.js');const trail=createNavigationTrail();
 assert.deepEqual(trail.back(),{key:'dashboard',query:'',open:null});
 trail.visit('dashboard');trail.visit('contents','école');trail.visit('contents','école');
 trail.visit('settings');assert.equal(trail.canBack,true);
 assert.deepEqual(trail.back(),{key:'contents',query:'école',open:null});
 assert.equal(trail.back().key,'dashboard');assert.equal(trail.canBack,false);
 trail.reset();assert.equal(trail.canBack,false);
});
test('retour depuis un détail : écran parent conservé',async()=>{
 const {createNavigationTrail}=await import('../src/navigation-admin.js');const trail=createNavigationTrail();
 trail.visit('lieux','Santé');trail.visit('lieux','Santé','fiche-1');
 assert.deepEqual(trail.back(),{key:'lieux',query:'Santé',open:null});
});
