import test from 'node:test';import assert from 'node:assert/strict';import fs from 'node:fs';import {createHash} from 'node:crypto';
import {bilanSante,problemesSante,etat} from '../src/sante-admin.js';
const S=globalThis.KokiSanteContract;
// Empreinte du contrat Santé : identique dans le site public (assets/portail/sante-contract.js).
const EMPREINTE='5c892278edc78b208fb5ca4b8618e96014b5de8d7b049b5374ae0732466867a6';
const base={genre:'Centre de santé',telephone:'+221 77 000 00 00',whatsapp:'',h24:false,plages:[{jours:[0,1,2,3,4],de:'08:00',a:'17:00'},{jours:[5],de:'08:00',a:'13:00'}],horaires_note:'',services:'Consultations, Vaccination',garde:false,garde_fin:'',latitude:15.5,longitude:-15.99,description:'',archive:false};
const row=(texte,extra={})=>({id:'1',type:'Informations utiles',categorie:'Santé',titre:'Centre de santé de Koki',resume:'r',lieu:'Koki',statut:'publié',publication:'2026-10-01T00:00:00Z',image_path:'a/b.jpg',texte,...extra});
// Dakar = UTC toute l'année. 13/10/2026 est un mardi.
const mardi10h=new Date('2026-10-13T10:00:00Z'),mardi18h=new Date('2026-10-13T18:00:00Z'),samedi12h=new Date('2026-10-17T12:00:00Z'),dimanche=new Date('2026-10-18T10:00:00Z');

test('contrat Santé : identique dans les deux dépôts',()=>{assert.equal(createHash('sha256').update(fs.readFileSync(new URL('../src/sante-contract.js',import.meta.url))).digest('hex'),EMPREINTE);});

test('contrat Santé : enregistrement, refus et horaires',()=>{
 const v=S.decode(row(S.encode(base)));assert.deepEqual(v.services,['Consultations','Vaccination']);
 assert.equal(S.ouvert(v,mardi10h),true);assert.equal(S.ouvert(v,mardi18h),false);assert.equal(S.ouvert(v,samedi12h),true);assert.equal(S.ouvert(v,dimanche),false);
 assert.equal(S.horairesTexte(v),'Lun–Ven 08h00–17h00 · Sam 08h00–13h00');
 assert.equal(S.ouvert(S.decode(row(S.encode({...base,plages:[]}))),mardi10h),null,'sans horaires : statut inconnu, jamais deviné');
 assert.equal(S.ouvert(S.decode(row(S.encode({...base,h24:true}))),dimanche),true);
 const nuit=S.decode(row(S.encode({...base,plages:[{jours:[1],de:'20:00',a:'06:00'}]})));
 assert.equal(S.ouvert(nuit,new Date('2026-10-13T22:00:00Z')),true);assert.equal(S.ouvert(nuit,new Date('2026-10-14T05:00:00Z')),true,'garde de nuit après minuit');assert.equal(S.ouvert(nuit,new Date('2026-10-14T07:00:00Z')),false);
 assert.throws(()=>S.encode({...base,genre:'Sorcier'}),/type/);
 assert.throws(()=>S.encode({...base,telephone:'abc'}),/téléphone/);
 assert.throws(()=>S.encode({...base,plages:[{jours:[],de:'08:00',a:'17:00'}]}),/Horaires/);
 assert.throws(()=>S.encode({...base,latitude:15.5,longitude:''}),/GPS/);
 assert.equal(S.decode({...row(S.encode(base)),categorie:'Éducation'}),null);assert.equal(S.decode(row('texte libre')),null);
});

test('pharmacie de garde : date de fin incluse',()=>{
 const v=S.decode(row(S.encode({...base,genre:'Pharmacie',garde:true,garde_fin:'2026-10-17'})));
 assert.equal(S.enGarde(v,samedi12h),true);assert.equal(S.enGarde(v,dimanche),false);assert.equal(S.famille(v.genre),'pharmacie');
});

test('Admin Santé : compteurs et points à vérifier',()=>{
 const rows=[row(S.encode(base)),row(S.encode({...base,telephone:'',plages:[],latitude:null,longitude:null}),{id:'2',statut:'brouillon',image_path:null}),row(S.encode({...base,genre:'Pharmacie',garde:true,garde_fin:'2026-10-20'}),{id:'3'}),row(S.encode({...base,archive:true}),{id:'4',statut:'brouillon'})];
 const b=bilanSante(rows,mardi10h);
 assert.deepEqual([b.total,b.publiees,b.brouillons,b.archivees,b.ouvertes,b.garde,b.aVerifier],[4,2,1,1,2,1,1]);
 assert.equal(problemesSante(rows[1],S.decode(rows[1])).length,4);assert.equal(etat(rows[3],true),'Archivée');
 const app=fs.readFileSync(new URL('../src/app.js',import.meta.url),'utf8');assert.match(app,/k==='sante'/);assert.match(app,/KokiSanteContract\?\.decode\(row\)/);
});
