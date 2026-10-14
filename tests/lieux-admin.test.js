// Lieux de la carte : contrat commun, inventaire (carte intégrée + corrections + ajouts), écran branché.
import test from 'node:test';import assert from 'node:assert/strict';import fs from 'node:fs';import {createHash} from 'node:crypto';
import {inventaire,bilanLieux,etatLieu,lireCoordonnees} from '../src/lieux-admin.js';
import {reference} from '../src/carte-reference.js';
const L=globalThis.KokiLieuContract;
// Empreintes : contrat identique dans le site public (assets/portail/lieu-contract.js) ; référence = lieux de assets/koki-carte.json.
const EMPREINTE='c5c581043dc9116c1b03abe5aa5ce36260cffe8c58535fa766ad1092c956107e',REFERENCE='8763e5d4991b0f287b2e171a65e5db09e98d098daf720a92ba402b5dc6500320';
const row=(titre,v,extra={})=>({id:extra.id||'r-'+titre,type:'Informations utiles',categorie:'Lieux de la carte',titre,resume:'r',lieu:'Koki',statut:'publié',publication:'2026-10-01T00:00:00Z',updated_at:'2026-10-01T00:00:00Z',texte:L.encode(v),...extra});
const mairie={genre:'Services publics',latitude:15.506,longitude:-15.992,description:'Ouverte du lundi au vendredi'};
test('contrat Lieux et référence de la carte : identiques au site public',()=>{
 assert.equal(createHash('sha256').update(fs.readFileSync(new URL('../src/lieu-contract.js',import.meta.url))).digest('hex'),EMPREINTE);
 assert.equal(createHash('sha256').update(JSON.stringify(reference)).digest('hex'),REFERENCE);
});
test('contrat : position dans la commune obligatoire, catégorie connue, masquage d’un lieu de la carte seulement',()=>{
 assert.ok(L.decode(row('Mairie',mairie)));
 assert.throws(()=>L.encode({...mairie,latitude:14.7,longitude:-17.4}),/commune de Koki/);
 assert.throws(()=>L.encode({...mairie,latitude:''}),/Position GPS requise/);
 assert.throws(()=>L.encode({...mairie,genre:'Santé'}),/catégorie/);
 assert.throws(()=>L.encode({...mairie,remplace:'osm/12'}),/introuvable/);
 assert.throws(()=>L.encode({...mairie,masque:true}),/Lieu invalide/);
 assert.equal(L.decode({...row('Mairie',mairie),categorie:'Santé'}),null);assert.equal(L.decode({...row('Mairie',mairie),texte:'{'}),null);
 assert.deepEqual(lireCoordonnees('15.5059, -15.9919'),{latitude:15.5059,longitude:-15.9919});assert.deepEqual(lireCoordonnees('15,5059 -15,9919'),{latitude:15.5059,longitude:-15.9919});
 assert.equal(lireCoordonnees('14.69, -17.44'),null);assert.equal(lireCoordonnees('n’importe quoi'),null);
});
test('fusion pour l’application : ajouts, corrections, masquage, archives et brouillons ignorés',()=>{
 const [a,b]=reference;
 const rows=[row('Mairie de Koki',mairie),row('Nom corrigé',{genre:'Eau',latitude:a.latitude,longitude:a.longitude,remplace:a.id}),row(b.nom,{genre:'Eau',latitude:b.latitude,longitude:b.longitude,remplace:b.id,masque:true}),
  row('Archivé',{...mairie,archive:true})];
 const lieux=L.fusionner(reference,rows);
 assert.equal(lieux.length,reference.length);assert.ok(lieux.some(l=>l.nom==='Mairie de Koki'&&l.categorie==='Services publics'&&l.id==='koki-r-Mairie de Koki'));
 assert.equal(lieux.find(l=>l.id===a.id).nom,'Nom corrigé');assert.ok(!lieux.some(l=>l.id===b.id));assert.ok(!lieux.some(l=>l.nom==='Archivé'));
 assert.equal(new Set(lieux.map(l=>l.id)).size,lieux.length);
});
test('inventaire de l’écran : chaque lieu de la carte une fois, avec sa dernière correction',()=>{
 const [a]=reference;
 const rows=[row('Ancienne',{genre:'Eau',latitude:a.latitude,longitude:a.longitude,remplace:a.id},{id:'1',updated_at:'2026-10-01T00:00:00Z'}),row('Récente',{genre:'Eau',latitude:a.latitude,longitude:a.longitude,remplace:a.id},{id:'2',updated_at:'2026-10-05T00:00:00Z'}),row('Mairie',mairie),row('Brouillon',mairie,{statut:'brouillon'})];
 const lignes=inventaire(rows);assert.equal(lignes.length,reference.length+2);assert.equal(lignes.find(x=>x.ref?.id===a.id).row.titre,'Récente');
 const b=bilanLieux(lignes);assert.equal(b.carte,reference.length);assert.equal(b.ajoutes,1);assert.equal(b.corriges,1);assert.equal(b.brouillons,1);assert.equal(b.parCategorie['Services publics'],1);
 assert.equal(etatLieu(null,{}),'Carte intégrée');assert.equal(etatLieu(rows[2],L.decode(rows[2]),Date.parse('2026-09-01')),'Programmé');
});
test('écran branché : menu Publications, rubriques Services publics, redirection de l’éditeur, sans innerHTML',()=>{
 const app=fs.readFileSync(new URL('../src/app.js',import.meta.url),'utf8'),ecran=fs.readFileSync(new URL('../src/lieux-admin.js',import.meta.url),'utf8');
 assert.match(app,/if\(k==='lieux'\)\{await renderLieux\(main,/);assert.match(app,/KokiLieuContract\?\.decode\(row\)\)\{await navigate\('lieux','',row\.id\)/);
 assert.equal(globalThis.KokiRubriquesContract?.rubriqueDe?.('lieux')?.nom??'Lieux de la carte','Lieux de la carte');
 assert.match(ecran,/can\(account\?\.role,'content'\)/);assert.doesNotMatch(ecran,/innerHTML/);
});
