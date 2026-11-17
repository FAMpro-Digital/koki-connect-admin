// Fiches signalées depuis l'application publique : tri, contrôle avant envoi et branchement dans l'écran Validations.
import test from 'node:test';import assert from 'node:assert/strict';import fs from 'node:fs';
import {verifierTraitement,trierFiches,MOTIFS,STATUTS} from '../src/fiches-signalees.js';
test('contrôle avant envoi : note obligatoire pour « Traité », 3 à 500 caractères',()=>{
 assert.equal(verifierTraitement('Traité',''),'Indiquez ce qui a été fait avant de marquer « Traité ».');
 assert.equal(verifierTraitement('En cours','ab'),'La note doit contenir de 3 à 500 caractères.');
 assert.equal(verifierTraitement('En cours',''),'');assert.equal(verifierTraitement('Traité','Fiche archivée'),'');assert.equal(verifierTraitement('Fermé','x'),'Statut invalide.');
});
test('tri : nouveaux, puis fiches les plus signalées, puis plus récents',()=>{
 const rows=[{id:'a',statut:'Traité',total:9,created_at:'2026-11-17T10:00:00Z'},{id:'b',statut:'Nouveau',total:1,created_at:'2026-11-17T09:00:00Z'},
  {id:'c',statut:'Nouveau',total:3,created_at:'2026-11-16T09:00:00Z'},{id:'d',statut:'En cours',total:1,created_at:'2026-11-17T11:00:00Z'}];
 assert.deepEqual(trierFiches(rows).map(r=>r.id),['c','b','d','a']);assert.deepEqual(trierFiches(null),[]);
});
test('mêmes motifs et statuts que le serveur ; écran ajouté sous Validations, appel au serveur protégé',()=>{
 assert.deepEqual(MOTIFS,['Arnaque ou fraude','Contenu choquant','Produit interdit','Fausses informations','Autre']);assert.deepEqual(STATUTS,['Nouveau','En cours','Traité']);
 const app=fs.readFileSync('src/app.js','utf8');assert.ok(app.includes("await renderValidations(main,{api:business,guard,can,account,imageURL,imagePreview,navigate});await renderFichesSignalees(main,{n,button,db,guard,can,account,navigate});"));
 const src=fs.readFileSync('src/fiches-signalees.js','utf8');assert.ok(src.includes("await guard();const {data,error}=await db.rpc('koki_record_reports_admin',args);"));assert.ok(src.includes("can(account?.role,'commerce')"));
});
