// Chaque rubrique a ses propres renseignements, numéros, lieux et catégories de publication.
import test from 'node:test';import assert from 'node:assert/strict';import fs from 'node:fs';
import '../src/rubriques-contract.js';
import {groupesRubrique} from '../src/numeros-admin.js';
import {categoriesPour,champsVisibles,categories} from '../src/model.js';
const R=globalThis.KokiRubriquesContract;
test('fiche Renseignements : une par rubrique, la plus récente gagne, validations',()=>{
 const t=JSON.parse(R.encodeFiche({cle:'sante',presentation:' Soins à Koki ',responsable:'Dr Ndiaye',telephone:'33 967 00 01',visible:false}));
 assert.deepEqual([t.presentation,t.visible],['Soins à Koki',false]);
 const ligne=(v,maj)=>({type:'Informations utiles',categorie:'Rubriques',titre:'Santé',texte:R.encodeFiche(v),updated_at:maj});
 const f=R.fiches([ligne({cle:'sante',presentation:'ancienne'},'2026-10-01T00:00:00Z'),ligne({cle:'sante',presentation:'nouvelle'},'2026-10-10T00:00:00Z'),ligne({cle:'transport'},'2026-10-02T00:00:00Z')]);
 assert.equal(f.sante.v.presentation,'nouvelle');assert.ok(f.transport);assert.equal(f.evenements,undefined);
 assert.throws(()=>R.encodeFiche({cle:'inconnue'}),/Rubrique inconnue/);assert.throws(()=>R.encodeFiche({cle:'sante',telephone:'abc'}),/Téléphone/);
 assert.equal(R.decodeFiche({type:'Informations utiles',categorie:'Santé',texte:t}),null);
});
test('numéros et lieux propres à la rubrique',()=>{
 assert.deepEqual(groupesRubrique(R,'sante').groupes,['Santé']);assert.deepEqual(groupesRubrique(R,'transport').groupes,['Transport']);
 assert.deepEqual(groupesRubrique(R,'services_publics').groupes,['Administration','Eau et électricité','Sécurité']);
 assert.equal(groupesRubrique(R,'').rubrique,null,'sans rubrique : tous les groupes');
 const lx=fs.readFileSync(new URL('../src/lieux-admin.js',import.meta.url),'utf8');assert.match(lx,/const propre=L\.genres\.includes\(ctx\.query\)\?ctx\.query:null;/);assert.match(lx,/for\(const x of propre\?\[propre\]:/);
 assert.deepEqual(['commerce','education','sports','services_publics'].map(c=>R.rubriques.find(r=>r.cle===c).lieux),['Commerces','Éducation','Sports','Services publics']);
});
test('publications : catégories et champs selon le type, type verrouillé dans une rubrique',()=>{
 assert.ok(categoriesPour('Annonces').includes('Avis important'));assert.ok(!categoriesPour('Annonces').includes('Match à venir'));
 assert.ok(categoriesPour('Annonces','Ancienne catégorie').includes('Ancienne catégorie'),'valeur enregistrée conservée');
 assert.deepEqual(categoriesPour('Publicités'),categories);
 assert.deepEqual(champsVisibles('Annonces'),{evenement:false,actif:false,emplacement:false,fin:false});assert.equal(champsVisibles('Publicités').emplacement,true);
 const app=fs.readFileSync(new URL('../src/app.js',import.meta.url),'utf8');
 assert.match(app,/const dansRubrique=content&&!!v\.type&&!!back&&back!=='contents';/);assert.match(app,/fields\.type\.addEventListener\('change',majChamps\);majChamps\(\);/);
 assert.match(app,/if\(k==='renseignements'\)\{await renderRenseignements\(main,/);assert.match(app,/const fiche=R\.decodeFiche\(row\);if\(fiche\)\{await navigate\('renseignements',fiche\.cle\);return;\}/);
 assert.match(app,/refresh:\(\)=>navigate\('numeros',query\),query,open/);
});
