import test from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {lirePosition,messageErreurPosition,textePosition,coordonneesValides,lienCarte} from '../src/position-gps.js';
import {resources,validateRecord} from '../src/model.js';

const geo=(coords,err)=>({getCurrentPosition:(ok,ko,opts)=>{geo.opts=opts;err?ko(err):ok({coords});}});

test('la position vient du GPS, arrondie, avec la précision', async()=>{
 const p=await lirePosition(geo({latitude:15.5601234567,longitude:-16.2109876543,accuracy:8.4}));
 assert.deepEqual(p,{latitude:15.560123,longitude:-16.210988,precision:8});
 assert.equal(geo.opts.enableHighAccuracy,true);assert.equal(geo.opts.maximumAge,0);
});
test('refus, absence de GPS, délai : messages clairs en français', async()=>{
 await assert.rejects(lirePosition(geo(null,{code:1})),/Localisation refusée/);
 await assert.rejects(lirePosition(geo(null,{code:3})),/trop de temps/);
 await assert.rejects(lirePosition(undefined),/ne permet pas la localisation/);
 await assert.rejects(lirePosition(geo({latitude:200,longitude:0})),/invalide/);
 assert.match(messageErreurPosition({code:2}),/introuvable/);
});
test('affichage et lien carte', ()=>{
 assert.equal(textePosition(NaN,NaN),'Aucune position enregistrée.');
 assert.equal(textePosition(15.56,-16.21,12),'Position enregistrée : 15.56000, -16.21000 (précision ± 12 m)');
 assert.ok(coordonneesValides(0,0));assert.ok(!coordonneesValides(91,0));
 assert.match(lienCarte(15.56,-16.21),/openstreetmap\.org\/\?mlat=15\.56&mlon=-16\.21/);
});
test('plus aucune saisie manuelle : le formulaire passe par le bloc GPS', ()=>{
 const app=readFileSync(new URL('../src/app.js',import.meta.url),'utf8');
 assert.match(app,/if\(key==='longitude'\)continue;if\(key==='latitude'\)\{positionField\(/);
 for(const kind of ['professionnels','chauffeurs'])assert.ok(resources[kind].fields.some(([k])=>k==='latitude'));
 // les coordonnées GPS restent validées à l'enregistrement
 assert.throws(()=>validateRecord('chauffeurs','Disponible',{nom:'TEST',latitude:120,longitude:0}),/Latitude invalide/);
 assert.doesNotThrow(()=>validateRecord('chauffeurs','Disponible',{nom:'TEST',latitude:null,longitude:null}));
});
