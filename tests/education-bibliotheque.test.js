import test from 'node:test';import assert from 'node:assert/strict';import {PGlite} from '@electric-sql/pglite';import {readFile} from 'node:fs/promises';
import {setupBusinessDB,actor,testActors} from './helpers/business-db.js';
import '../src/livre-contract.js';
const L=globalThis.KokiLivreContract;
const base={categorie:'Scolaire',niveau:'3e',format:'PDF',acces:'Gratuit',prix:0,auteur:'',fournisseur:'',whatsapp:'',description:'',taille_mo:1,archive:false};
const A=testActors.admin,E=testActors.editor;
const f=n=>A+'/aaaa1111-0000-4000-8000-00000000000'+n+'.pdf';

test('Bibliothèque : seul le fichier d’un livre gratuit publié est lisible par le public',async()=>{
 const pg=new PGlite(),db={query:(q,v)=>v?pg.query(q,v):pg.exec(q).then(x=>x.at(-1))};try{
  await setupBusinessDB(db);
  await db.query(await readFile(new URL('../supabase/proposals/education-bibliotheque.sql',import.meta.url),'utf8'));
  const bucket=(await db.query("select file_size_limit,allowed_mime_types from storage.buckets where id='koki-livres'")).rows[0];
  assert.equal(Number(bucket.file_size_limit),50*1024*1024);assert.ok(bucket.allowed_mime_types.includes('application/pdf'));
  const payant=JSON.stringify({schema:L.marker,version:1,...base,acces:'Payant',prix:2000,fichier:f(4)});
  const rows=[['Gratuit publié','publié','-1 hour',L.encode({...base,fichier:f(1)})],['Gratuit brouillon','brouillon','-1 hour',L.encode({...base,fichier:f(2)})],
   ['Gratuit archivé','publié','-1 hour',L.encode({...base,fichier:f(3),archive:true})],['Payant forcé','publié','-1 hour',payant],
   ['Texte libre','publié','-1 hour','pas du json '+f(5)],['Programmé','publié','+1 day',L.encode({...base,fichier:f(5)})]];
  await db.query('reset role');await db.query("select set_config('request.jwt.claim.sub',$1,false)",[A]);
  for(const [titre,statut,delta,texte] of rows)await db.query("insert into koki_contents(type,categorie,titre,resume,statut,publication,texte) values('Informations utiles','Éducation',$1,'r',$2,now()+$3::interval,$4)",[titre,statut,delta,texte]);
  for(const n of [1,2,3,4,5])await db.query("insert into storage.objects(bucket_id,name) values('koki-livres',$1)",[f(n)]);
  await actor(db,null,'aal1','anon');
  assert.deepEqual((await db.query("select name from storage.objects where bucket_id='koki-livres'")).rows.map(r=>r.name),[f(1)]);
  await actor(db,A,'aal1');
  await assert.rejects(db.query("insert into storage.objects(bucket_id,name) values('koki-livres',$1)",[A+'/sans-mfa.pdf']));
  await actor(db,A,'aal2');
  assert.equal((await db.query("select count(*)::int as n from storage.objects where bucket_id='koki-livres'")).rows[0].n,5);
  await db.query("insert into storage.objects(bucket_id,name) values('koki-livres',$1)",[A+'/nouveau.pdf']);
  await assert.rejects(db.query("insert into storage.objects(bucket_id,name) values('koki-livres',$1)",[E+'/autre-dossier.pdf']));
  assert.equal((await db.query("delete from storage.objects where bucket_id='koki-livres' and name=$1 returning 1",[f(1)])).rows.length,0,'fichier encore référencé');
  assert.equal((await db.query("delete from storage.objects where bucket_id='koki-livres' and name=$1 returning 1",[A+'/nouveau.pdf'])).rows.length,1);
  await actor(db,E,'aal2');await db.query("insert into storage.objects(bucket_id,name) values('koki-livres',$1)",[E+'/editeur.pdf']);
 }finally{await pg.close();}
});

test('Contrat livre : identique au site public et sans fichier pour un livre payant',async()=>{
 const admin=await readFile(new URL('../src/livre-contract.js',import.meta.url),'utf8');
 assert.match(admin,/koki\.education\.book/);
 const paye=L.decode({type:'Informations utiles',categorie:'Éducation',texte:L.encode({...base,acces:'Payant',prix:1500,fichier:f(1)})});
 assert.equal(paye.fichier,'');assert.equal(L.telechargeable(paye),false);
 assert.throws(()=>L.encode({...base,taille_mo:60}),/50 Mo/);
 assert.equal(L.tailleMax,50);
});
