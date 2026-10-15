// Événements (administration) : contrat commun, états de l'agenda, fichier agenda, écran branché.
import test from 'node:test';import assert from 'node:assert/strict';import fs from 'node:fs';import {createHash} from 'node:crypto';
import '../src/rubriques-contract.js';
import {etatEvenement,bilanEvenements} from '../src/evenements-admin.js';
const E=globalThis.KokiEvenementContract;
const EMPREINTE='542e25f1dcb67155c94d5935323cbe6d08f409654463fb8dcc8ba1345bcc0303';
const now=Date.parse('2026-10-15T10:00:00Z');// jeudi
const row=(debut,v={},extra={})=>({id:'e1',type:'Événements',titre:'Magal de Koki',resume:'Grande cérémonie',lieu:'Grande mosquée',statut:'publié',evenement:debut,texte:v===null?'Texte libre':E.encode(v),...extra});
test('contrat Événement : identique dans le site public',()=>{assert.equal(createHash('sha256').update(fs.readFileSync(new URL('../src/evenement-contract.js',import.meta.url))).digest('hex'),EMPREINTE);});
test('états : à venir, en cours (4 h par défaut), terminé, brouillon, archivé, ancien événement',()=>{
 const etat=(d,v,extra)=>{const r=row(d,v,extra);return etatEvenement(r,E.decode(r),now);};
 assert.equal(etat('2026-10-16T18:00:00Z',{genre:'Religieux'}),'À venir');
 assert.equal(etat('2026-10-15T08:00:00Z',{}),'En cours');assert.equal(etat('2026-10-15T05:00:00Z',{}),'Terminé');
 assert.equal(etat('2026-10-15T05:00:00Z',{fin:'2026-10-15T12:00:00Z'}),'En cours');
 assert.equal(etat('2026-10-16T18:00:00Z',{},{statut:'brouillon'}),'Brouillon');assert.equal(etat('2026-10-16T18:00:00Z',{archive:true}),'Archivé');
 assert.equal(etat('2026-10-16T18:00:00Z',null),'À venir');
 const b=bilanEvenements([row('2026-10-16T18:00:00Z',{}),row('2026-11-20T18:00:00Z',{}),row('2026-10-15T08:00:00Z',{}),row('2026-10-01T08:00:00Z',{}),row('2026-10-20T08:00:00Z',{},{statut:'brouillon'})],now);
 assert.deepEqual(b,{aVenir:2,enCours:1,semaine:2,termines:1,brouillons:1});
});
test('contrat : quand, périodes, fichier agenda avec rappel, validations',()=>{
 const v=JSON.parse(E.encode({genre:'Culture',organisateur:'ASC Koki',contact:'+221 77 000 00 00',latitude:'15.5',longitude:'-16.1'}));
 assert.equal(E.quand(row('2026-10-15T18:00:00Z'),v,now),'Aujourd’hui · 18:00');assert.equal(E.quand(row('2026-10-16T17:00:00Z'),v,now),'Demain · 17:00');
 assert.equal(E.periode('Ce week-end',row('2026-10-17T18:00:00Z'),v,now),true);assert.equal(E.periode('Ce week-end',row('2026-10-20T18:00:00Z'),v,now),false);
 assert.equal(E.periode('Cette semaine',row('2026-10-18T18:00:00Z'),v,now),true);assert.equal(E.periode('Ce mois',row('2026-11-02T18:00:00Z'),v,now),false);
 const ics=E.ics(row('2026-10-16T18:00:00Z'),v);assert.match(ics,/DTSTART:20261016T180000Z/);assert.match(ics,/DTEND:20261016T220000Z/);assert.match(ics,/TRIGGER:-PT2H/);assert.match(ics,/GEO:15.5;-16.1/);
 assert.throws(()=>E.encode({genre:'Inventé'}),/type d’événement/);assert.throws(()=>E.encode({contact:'abc'}),/Téléphone/);assert.throws(()=>E.encode({latitude:'15'}),/GPS/);
 assert.equal(E.decode({type:'Événements',texte:'Texte libre'}),null);
});
test('écran branché : rubrique, routage, éditeur, menu',()=>{
 const app=fs.readFileSync(new URL('../src/app.js',import.meta.url),'utf8'),ad=fs.readFileSync(new URL('../src/evenements-admin.js',import.meta.url),'utf8');
 assert.match(app,/import \{renderEvenements\} from '\.\/evenements-admin\.js';/);
 assert.match(app,/if\(k==='contenus:Événements'\)k='evenements';/);
 assert.match(app,/if\(k==='evenements'\)\{await renderEvenements\(main,/);
 assert.match(app,/if\(row\?\.type==='Événements'\)\{await navigate\('evenements','',row\.id\|\|null\);return;\}/);
 assert.match(ad,/positionField\(f,x,/);assert.match(ad,/evenement:debut/);assert.doesNotMatch(ad,/innerHTML/);
 const R=globalThis.KokiRubriquesContract;assert.deepEqual(R.rubriques.find(r=>r.cle==='evenements').ecrans.map(e=>[...e]),[['evenements','Agenda des événements']]);
});
