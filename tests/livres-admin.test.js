import test from 'node:test';import assert from 'node:assert/strict';import fs from 'node:fs';
import {formatLivre,verifierLivre,formatContrat,LIVRE_MAX_OCTETS} from '../src/livre-fichier.js';
import {bilanEducation,problemesLivre,etat} from '../src/livres-admin.js';
const L=globalThis.KokiLivreContract,S=globalThis.KokiEducationContract;
const blob=(bytes,size)=>{const b=new Blob([bytes]);if(size)Object.defineProperty(b,'size',{value:size});return b;};

test('Fichiers de livres : vrai format vérifié, taille limitée',async()=>{
 assert.equal(await formatLivre(blob('%PDF-1.7\n')),'application/pdf');
 const epub=new Uint8Array(64);epub.set([0x50,0x4b,0x03,0x04]);epub.set([...'mimetypeapplication/epub+zip'].map(c=>c.charCodeAt(0)),30);
 assert.equal(await formatLivre(blob(epub)),'application/epub+zip');
 assert.equal(await formatLivre(blob('ID3\u0004')),'audio/mpeg');
 assert.equal(await formatLivre(blob(new Uint8Array([0,0,0,32,...[...'ftypM4A '].map(c=>c.charCodeAt(0))]))),'audio/mp4');
 assert.equal(await formatLivre(blob('<html>')),null);
 assert.equal(await formatLivre(blob(new Uint8Array([0x50,0x4b,0x03,0x04,0,0]))),null,'un zip quelconque n’est pas un EPUB');
 await assert.rejects(verifierLivre(blob('MZ exécutable')),/Format refusé/);
 await assert.rejects(verifierLivre(blob('%PDF-1.7',LIVRE_MAX_OCTETS+1)),/50 Mo/);
 const ok=await verifierLivre(blob('%PDF-1.7',3*1048576));assert.deepEqual([ok.ext,ok.taille_mo],['pdf',3]);
 assert.equal(formatContrat('audio/mpeg','PDF'),'Audio');assert.equal(formatContrat('application/pdf','Audio + PDF'),'Audio + PDF');
});

test('Vue d’ensemble Éducation : compteurs réels et points à vérifier',()=>{
 const now=Date.parse('2026-10-13T12:00:00Z'),pub='2026-10-01T00:00:00Z',row=(titre,texte,extra={})=>({id:titre,type:'Informations utiles',categorie:'Éducation',titre,resume:'r',statut:'publié',publication:pub,image_path:'a/b.jpg',texte,...extra});
 const livre={categorie:'Scolaire',niveau:'3e',format:'PDF',acces:'Gratuit',prix:0,auteur:'',fournisseur:'',whatsapp:'',description:'',fichier:'1111/2222.pdf',taille_mo:2,archive:false};
 const rows=[
  row('École A',S.encode({niveau:'Élémentaire',secteur:'Public',telephone:'770000000',horaires:'8h-17h',description:'',archive:false})),
  row('École B',S.encode({niveau:'Moyen',secteur:'Public',telephone:'',horaires:'',description:'',archive:false}),{statut:'brouillon'}),
  row('Livre gratuit',L.encode(livre)),
  row('Livre sans fichier',L.encode({...livre,fichier:'',taille_mo:0})),
  row('Livre payant',L.encode({...livre,acces:'Payant',prix:2000,fichier:''}),{publication:'2026-10-20T00:00:00Z'}),
  row('Livre archivé',L.encode({...livre,archive:true}),{statut:'brouillon'}),
  row('Actualité Éducation','texte libre')
 ];
 const b=bilanEducation(rows,now);
 assert.deepEqual([b.ecoles.total,b.ecoles.Publié,b.ecoles.Brouillon,b.ecoles.aVerifier],[2,1,1,1]);
 assert.deepEqual([b.livres.total,b.livres.Publié,b.livres.Programmé,b.livres.Archivé,b.livres.gratuits,b.livres.payants,b.livres.telechargeables],[4,2,1,1,2,1,1]);
 assert.equal(b.livres.aVerifier,2,'sans fichier + payant sans WhatsApp');
 assert.ok(b.alertes.some(a=>a.row.titre==='Livre sans fichier'&&/sans fichier/.test(a.problemes[0])));
 assert.deepEqual(problemesLivre(rows[5],L.decode(rows[5])),[],'archivé : rien à signaler');
 assert.equal(etat(rows[4],false,now),'Programmé');
});

test('Rubrique Éducation : Vue d’ensemble, établissements et bibliothèque dans le menu',()=>{
 const app=fs.readFileSync(new URL('../src/app.js',import.meta.url),'utf8');
 assert.match(app,/k==='livres'/);assert.match(app,/k==='education-apercu'/);assert.match(app,/KokiLivreContract\?\.decode\(row\)/);
 const backend=fs.readFileSync(new URL('../src/backend.js',import.meta.url),'utf8');
 assert.match(backend,/from\('koki-livres'\)\.upload/);assert.match(backend,/createSignedUrl\(path,300\)/);
});
