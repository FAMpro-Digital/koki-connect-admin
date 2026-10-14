// Sports & ASC (administration) : contrat commun, lecture des équipes et matchs, dates, écrans branchés.
import test from 'node:test';import assert from 'node:assert/strict';import fs from 'node:fs';import {createHash} from 'node:crypto';
import {lireSport,etatSport,versISO,versChamp} from '../src/sport-admin.js';
const S=globalThis.KokiSportContract;
const EMPREINTE='3cb5bae2c82cdcccf115f26093110e4566b38028f659c5fa0a136b7d56f1022f';
const A='11111111-1111-4111-8111-111111111111',B='22222222-2222-4222-8222-222222222222';
const base={type:'Sports & ASC',statut:'publié',publication:'2026-10-01T00:00:00Z',lieu:'Koki',evenement:null};
test('contrat Sports : identique dans le site public',()=>{assert.equal(createHash('sha256').update(fs.readFileSync(new URL('../src/sport-contract.js',import.meta.url))).digest('hex'),EMPREINTE);});
test('lecture : équipes, matchs triés par date, terrain et date du match',()=>{
 const rows=[{...base,id:A,categorie:'Équipe',titre:'ASC Jamm',texte:S.encodeEquipe({couleurs:['#087a3d']})},{...base,id:B,categorie:'Équipe',titre:'ASC Diappo',texte:S.encodeEquipe({})},
  {...base,id:'m2',categorie:'Match',titre:'x',lieu:'Stade',evenement:'2026-10-12T17:00:00Z',texte:S.encodeMatch({competition:'Navétanes 2026',domicile:A,exterieur:B,statut:'Terminé',score_domicile:2,score_exterieur:0})},
  {...base,id:'m1',categorie:'Match',titre:'x',evenement:'2026-10-05T17:00:00Z',texte:S.encodeMatch({competition:'Navétanes 2026',domicile:B,exterieur:A})},{...base,id:'z',categorie:'Résultat',titre:'Article',texte:''}];
 const {equipes,matchs}=lireSport(rows);assert.equal(equipes.size,2);assert.deepEqual(matchs.map(m=>m.id),['m1','m2']);assert.equal(matchs[1].terrain,'Stade');
 assert.equal(S.classement(matchs,equipes,{competition:'Navétanes 2026'})[0].nom,'ASC Jamm');
 assert.equal(etatSport({statut:'brouillon'},{archive:false}),'Brouillon');assert.equal(etatSport({statut:'publié',publication:'2026-01-01'},{archive:true}),'Archivé');
 assert.equal(versISO('2026-10-19T17:00'),'2026-10-19T17:00:00.000Z');assert.equal(versChamp('2026-10-19T17:00:00.000Z'),'2026-10-19T17:00');
});
test('écrans branchés dans le menu Sports, redirection de l’éditeur, sans innerHTML',()=>{
 const app=fs.readFileSync(new URL('../src/app.js',import.meta.url),'utf8'),ecran=fs.readFileSync(new URL('../src/sport-admin.js',import.meta.url),'utf8');
 assert.match(app,/if\(k==='sport-matchs'\|\|k==='sport-equipes'\)\{await \(k==='sport-matchs'\?renderMatchs:renderEquipes\)\(main,/);
 assert.match(app,/KokiSportContract\?\.decodeMatch\(row\)\)\{await navigate\('sport-matchs','',row\.id\)/);
 assert.equal(globalThis.KokiRubriquesContract?.rubriqueDe?.('sport-matchs')?.nom??'Sports & ASC','Sports & ASC');
 assert.match(ecran,/can\(account\?\.role,'content'\)/);assert.doesNotMatch(ecran,/innerHTML/);
});
