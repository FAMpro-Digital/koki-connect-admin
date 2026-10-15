// Rubriques coordonnées : le menu de l'administration suit exactement l'accueil de l'application publique.
import test from 'node:test';import assert from 'node:assert/strict';import fs from 'node:fs';import {createHash} from 'node:crypto';
import '../src/rubriques-contract.js';import '../src/numeros-contract.js';import {types,categories,resources} from '../src/model.js';
const R=globalThis.KokiRubriquesContract,FICHIER=new URL('../src/rubriques-contract.js',import.meta.url);
// Empreinte du contrat : identique dans les deux dépôts (public : assets/portail/rubriques-contract.js).
const EMPREINTE='a501b77a3b0cc47c46d9c0ad328680798fdcf0e88ba2a845bb1c28930efb6b4a';
test('contrat Rubriques : identique dans les deux dépôts',()=>{assert.equal(createHash('sha256').update(fs.readFileSync(FICHIER)).digest('hex'),EMPREINTE);});
test('les 8 rubriques de l’accueil public, dans le même ordre',()=>{
 assert.deepEqual(R.rubriques.map(r=>r.nom),['Transport','Commerces & Services','Éducation','Emplois & Opportunités','Sport','Santé','Événements','Services publics']);
 assert.equal(new Set(R.rubriques.map(r=>r.cle)).size,8);for(const r of R.rubriques)assert.match(r.couleur,/^#[0-9a-f]{6}$/);
});
test('chaque type de contenu appartient à une seule rubrique ou publication',()=>{
 const owners=[...R.rubriques,...R.publications].filter(x=>x.type).map(x=>x.type);
 assert.deepEqual([...owners].sort(),[...types].sort());
 for(const t of types)assert.equal(R.rubriqueDe('contenus:'+t).type,t);
});
test('chaque écran métier et chaque écran dédié est rangé dans une seule rubrique',()=>{
 const ecrans=R.rubriques.flatMap(r=>r.ecrans.map(([k])=>k));assert.equal(new Set(ecrans).size,ecrans.length);
 for(const k of Object.keys(resources))assert.ok(ecrans.includes(k),k+' sans rubrique');
 for(const k of ['boutique-en-ligne','validations','education','education-apercu','livres','sante','signalements'])assert.ok(ecrans.includes(k));
 assert.equal(R.rubriqueDe('numeros').nom,'Numéros utiles');
 for(const k of ecrans)assert.ok(R.rubriqueDe(k),k);
});
test('sous-rubriques, catégories et groupes de numéros existent réellement',()=>{
 for(const [type,liste]of Object.entries(R.sousRubriques)){assert.ok(types.includes(type));for(const s of liste)for(const c of s.categories)assert.ok(categories.includes(c),c);}
 assert.deepEqual(R.sousRubriques['Opportunités'].map(s=>s.nom),['Emplois','Stages','Formations','Concours','Bourses','Financements']);
 const groupes=globalThis.KokiNumeroContract.groupes;for(const r of R.rubriques)for(const g of r.numeros||[])assert.ok(groupes.includes(g),g);
 for(const r of R.rubriques)if(r.categorie)assert.ok(categories.includes(r.categorie));
});
test('le menu de l’administration est construit à partir du contrat, sans liste figée',()=>{
 const app=fs.readFileSync(new URL('../src/app.js',import.meta.url),'utf8');
 assert.match(app,/import '\.\/rubriques-contract\.js';/);assert.match(app,/for\(const r of R\.rubriques\)/);assert.match(app,/for\(const x of R\.publications\)/);
 assert.doesNotMatch(app,/\['contents','📰 Contenus & publicités'\]/);assert.doesNotMatch(app,/Object\.entries\(resources\)\.map/);
 assert.match(app,/\['rubriques','🧭 Rubriques'\]/);
});
