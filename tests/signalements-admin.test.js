// Transport · Signalements : bilan, tri (Sécurité d'abord), lecture seule par le serveur.
import test from 'node:test';import assert from 'node:assert/strict';import fs from 'node:fs';
import {bilanSignalements,trierSignalements,MOTIFS} from '../src/signalements-admin.js';
const maintenant=Date.parse('2026-10-14T18:00:00Z');
const rows=[{motif:'Prix',statut:'Nouveau',created_at:'2026-10-14T10:00:00Z'},{motif:'Sécurité',statut:'Traité',created_at:'2026-10-01T10:00:00Z'},{motif:'Sécurité',statut:'Nouveau',created_at:'2026-10-13T10:00:00Z'},{motif:'Autre',statut:'En cours',created_at:'2026-10-14T12:00:00Z'}];
test('bilan : total, sécurité, nouveaux, 7 derniers jours, par motif',()=>{
 const b=bilanSignalements(rows,maintenant);assert.deepEqual([b.total,b.securite,b.nouveaux,b.semaine],[4,2,2,3]);assert.deepEqual(Object.keys(b.parMotif),MOTIFS);
 assert.deepEqual(bilanSignalements(null),{total:0,securite:0,nouveaux:0,semaine:0,parMotif:Object.fromEntries(MOTIFS.map(m=>[m,0]))});
});
test('tri : Sécurité d’abord, puis les plus récents',()=>{
 assert.deepEqual(trierSignalements(rows).map(r=>r.motif+' '+r.created_at.slice(5,10)),['Sécurité 10-13','Sécurité 10-01','Autre 10-14','Prix 10-14']);
});
test('écran branché : menu Transport, lecture serveur sans clé de reprise, droit Transport',()=>{
 const app=fs.readFileSync(new URL('../src/app.js',import.meta.url),'utf8'),cl=fs.readFileSync(new URL('../src/business-client.js',import.meta.url),'utf8'),ecran=fs.readFileSync(new URL('../src/signalements-admin.js',import.meta.url),'utf8');
 assert.match(app,/if\(k==='signalements'\)\{await renderSignalements\(main,/);assert.match(cl,/'admin_ride_reports'\]\);/);
 assert.match(ecran,/can\(account\?\.role,'transport'\)/);assert.match(ecran,/api\.run\('admin_ride_reports',\{\}\)/);assert.doesNotMatch(ecran,/innerHTML/);
 assert.equal(globalThis.KokiRubriquesContract?.rubriqueDe?.('signalements')?.nom??'Transport','Transport');
});
