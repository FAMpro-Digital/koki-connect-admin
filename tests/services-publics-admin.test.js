// Services publics (administration) : contrat commun, contrôles des fiches, bilan, écrans branchés.
import test from 'node:test';import assert from 'node:assert/strict';import fs from 'node:fs';import {createHash} from 'node:crypto';
import '../src/rubriques-contract.js';
import {etat,problemesService,problemesDemarche,bilanServices} from '../src/services-publics-admin.js';
const S=globalThis.KokiServiceContract,R=globalThis.KokiRubriquesContract;
const EMPREINTE='fa8a147fbb88c4befd32fca49a6f01a14d35128ba6290681a955b185900a5634';
const now=new Date('2026-10-15T10:00:00Z');
const svc=(v,extra={})=>({id:'00000000-0000-4000-8000-000000000001',type:'Informations utiles',categorie:'Services publics',titre:'Mairie',lieu:'Koki',statut:'publié',publication:'2026-10-01T00:00:00Z',texte:S.encodeService({genre:'Mairie',...v}),...extra});
const dem=(v,extra={})=>({id:'d1',type:'Informations utiles',categorie:'Démarches administratives',titre:'Acte',lieu:'',statut:'publié',publication:'2026-10-01T00:00:00Z',texte:S.encodeDemarche({domaine:'État civil',...v}),...extra});
test('contrat Services publics : identique dans le site public',()=>{assert.equal(createHash('sha256').update(fs.readFileSync(new URL('../src/service-contract.js',import.meta.url))).digest('hex'),EMPREINTE);});
test('contrôles : fiche incomplète, démarche sans lieu ou liée à un service supprimé',()=>{
 const s=svc({}),v=S.decodeService(s);assert.equal(problemesService(s,v).length,3);
 const complet=svc({telephone:'33 967 00 00',plages:[{jours:[0,1,2,3,4],de:'08:00',a:'17:00'}],latitude:15.5,longitude:-16});assert.deepEqual(problemesService(complet,S.decodeService(complet)),[]);
 const d=dem({pieces:'Pièce d’identité',service:'00000000-0000-4000-8000-000000000009'});assert.match(problemesDemarche(d,S.decodeDemarche(d),[s]).join(),/n’existe plus/);
 assert.match(problemesDemarche(dem({}),S.decodeDemarche(dem({})),[]).join(),/Aucune pièce.*Lieu/);
 assert.equal(etat(s,false,now.getTime()),'Publiée');assert.equal(etat(s,true),'Archivée');
});
test('bilan : services, ouverts maintenant, démarches, avis récents',()=>{
 const rows=[svc({plages:[{jours:[0,1,2,3,4],de:'08:00',a:'17:00'}]}),svc({},{statut:'brouillon'}),dem({pieces:'X'},{lieu:'Mairie'}),
  {type:'Annonces',categorie:'Avis important',titre:'Coupure',statut:'publié',publication:'2026-10-14T08:00:00Z'},{type:'Annonces',categorie:'Communiqué',titre:'Ancien',statut:'publié',publication:'2026-08-01T08:00:00Z'},{type:'Annonces',categorie:'Petite annonce',titre:'Moto',statut:'publié',publication:'2026-10-14T08:00:00Z'}];
 const b=bilanServices(rows,now);assert.deepEqual([b.services,b.ouverts,b.demarches,b.avis],[1,1,1,1]);
});
test('écrans branchés : rubrique, routage, éditeur',()=>{
 const app=fs.readFileSync(new URL('../src/app.js',import.meta.url),'utf8'),ad=fs.readFileSync(new URL('../src/services-publics-admin.js',import.meta.url),'utf8');
 assert.deepEqual(R.rubriques.find(r=>r.cle==='services_publics').ecrans.map(e=>e[0]),['services-publics','demarches','avis-officiels']);
 assert.match(app,/import \{renderServicesPublics\} from '\.\/services-publics-admin\.js';/);
 assert.match(app,/if\(k==='services-publics'\|\|k==='demarches'\|\|k==='avis-officiels'\)\{await renderServicesPublics\(main,/);
 assert.match(app,/decodeService\(row\)\)\{await navigate\('services-publics','',row\.id\);return;\}/);assert.match(app,/decodeDemarche\(row\)\)\{await navigate\('demarches','',row\.id\);return;\}/);
 assert.match(ad,/positionField\(f,gps,/);assert.doesNotMatch(ad,/innerHTML/);
});
