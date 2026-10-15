// Emplois & Opportunités (administration) : contrat commun, états des offres, écran branché.
import test from 'node:test';import assert from 'node:assert/strict';import fs from 'node:fs';import {createHash} from 'node:crypto';
import {etatOffre,bilanOffres} from '../src/offres-admin.js';
const O=globalThis.KokiOffreContract;
const EMPREINTE='17b9863718b08fba9305f1c99155bbd1a242535f77e0cd338269735c9650524c';
const now=new Date('2026-10-15T10:00:00Z');
const row=(v,extra={})=>({type:'Opportunités',categorie:'Emploi',titre:'Offre',statut:'publié',publication:'2026-10-01T00:00:00Z',texte:v===null?'Texte libre':O.encode(v),...extra});
test('contrat Offre : identique dans le site public',()=>{assert.equal(createHash('sha256').update(fs.readFileSync(new URL('../src/offre-contract.js',import.meta.url))).digest('hex'),EMPREINTE);});
test('états : en ligne, se termine bientôt, expirée, brouillon, archivée, ancienne offre',()=>{
 const etat=(v,extra)=>etatOffre(row(v,extra),v===null?null:O.decode(row(v,extra)),now);
 assert.equal(etat({date_limite:'2026-12-01'}),'En ligne');assert.equal(etat({date_limite:'2026-10-20'}),'Se termine bientôt');
 assert.equal(etat({date_limite:'2026-10-14'}),'Expirée');assert.equal(etat({},{statut:'brouillon'}),'Brouillon');assert.equal(etat({archive:true}),'Archivée');assert.equal(etat(null),'En ligne');
 const b=bilanOffres([row({date_limite:'2026-12-01'}),row({date_limite:'2026-10-20'}),row({date_limite:'2026-10-14'}),row({}),row(null)],now);
 assert.deepEqual([b.enLigne,b.bientot,b.expirees,b.sansDate],[4,1,1,2],"offres sans date limite, anciennes comprises");
});
test('écran branché : contenus Opportunités redirigés vers les offres, éditeur redirigé, sans innerHTML',()=>{
 const app=fs.readFileSync(new URL('../src/app.js',import.meta.url),'utf8'),ecran=fs.readFileSync(new URL('../src/offres-admin.js',import.meta.url),'utf8');
 assert.match(app,/if\(String\(k\)\.startsWith\('contenus:Opportunités'\)\)\{query=String\(k\)\.split\(':'\)\[2\]\|\|query;k='offres';\}/);
 assert.match(app,/if\(k==='offres'\)\{await renderOffres\(main,/);assert.match(app,/if\(row\?\.type==='Opportunités'&&row\?\.id\)\{await navigate\('offres','',row\.id\);return;\}/);
 assert.equal(globalThis.KokiRubriquesContract?.rubriqueDe?.('offres')?.nom??'Emplois & Opportunités','Emplois & Opportunités');
 assert.match(ecran,/can\(account\?\.role,'content'\)/);assert.doesNotMatch(ecran,/innerHTML/);
});
