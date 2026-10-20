import test from 'node:test';import assert from 'node:assert/strict';import {readFile} from 'node:fs/promises';import {PGlite} from '@electric-sql/pglite';
import {setupBusinessDB,actor,testActors,fixtureBusiness} from './helpers/business-db.js';
// Environnement TEST uniquement (base en mémoire) : vérifie la proposition feed-pagine-quotas.sql avant toute installation distante.
const sqlFile=()=>readFile(new URL('../supabase/proposals/feed-pagine-quotas.sql',import.meta.url),'utf8');
async function prepare(){
 const pg=new PGlite(),db={query:(q,v)=>v?pg.query(q,v):pg.exec(q).then(x=>x.at(-1))};
 await setupBusinessDB(db);await db.query(await sqlFile());return {pg,db};
}
const ids=r=>r.contenus.map(x=>x.id);
const page=async(db,...args)=>(await db.query('select public.koki_public_feed_page($1,$2,$3) as r',args)).rows[0].r;
test('flux paginé : mêmes contenus que le flux complet, sans doublon ni perte, curseur stable',async()=>{
 const {pg,db}=await prepare();
 try{
  await db.query('reset role');
  // 5 publications, dont 2 à la même seconde, + un brouillon et une publication à venir (jamais visibles).
  await db.query(`insert into public.koki_contents(type,titre,resume,statut,publication) values
   ('Actualités','A','r','publié',now()-interval '1 minute'),('Actualités','B','r','publié',now()-interval '2 minutes'),
   ('Actualités','C','r','publié',now()-interval '3 minutes'),('Annonces','D1','r','publié',now()-interval '4 minutes'),
   ('Annonces','D2','r','publié',now()-interval '4 minutes')`);
  await db.query(`update public.koki_contents set publication=(select publication from public.koki_contents where titre='D1') where titre='D2'`);
  await db.query(`insert into public.koki_contents(type,titre,resume,statut,publication) values('Actualités','Brouillon','r','brouillon',now()-interval '1 minute'),('Actualités','Futur','r','publié',now()+interval '1 day')`);
  await actor(db,null,'aal1','anon');
  const complet=(await db.query('select public.koki_public_feed() as r')).rows[0].r;
  assert.equal(complet.contenus.length,5);
  const vus=[];let curseur=null,pages=0;
  do{const p=await page(db,2,curseur&&curseur.avant,curseur&&curseur.avant_id);assert.equal(p.version,1);assert.ok(p.contenus.length<=2);vus.push(...ids(p));curseur=p.suivant;pages++;}while(curseur&&pages<10);
  assert.equal(pages,3);assert.equal(vus.length,5);assert.equal(new Set(vus).size,5,'aucun doublon, même avec deux publications simultanées');
  assert.deepEqual([...vus].sort(),ids(complet).sort(),'mêmes contenus que koki_public_feed()');
  assert.equal((await page(db,2,null,null)).contenus[0].titre,'A','du plus récent au plus ancien');
  assert.equal((await page(db,1000,null,null)).contenus.length,5,'limite plafonnée à 50, tout tient en une page');
  assert.equal((await page(db,1000,null,null)).suivant,null);
  assert.equal((await page(db,0,null,null)).contenus.length,1,'limite minimale de 1');
  assert.equal((await page(db,null,null,null)).contenus.length,5,'limite par défaut');
 }finally{await pg.close();}
});
test('quotas : demandes d\'un client (60/heure, 300/jour) et créations d\'un professionnel (500/jour)',async()=>{
 const {pg,db}=await prepare();
 try{
  const f=await fixtureBusiness(db);await db.query('reset role');
  await db.query('alter table public.koki_records disable trigger business_relations'); // les relations métier sont testées ailleurs ; seul le quota est visé ici
  const lien=`'${f.shop.id}','${f.merchant.id}'`;
  const demande=`insert into public.koki_records(kind,statut,payload,client_id,parent_id,provider_id) values('commandes','Livrée','{"nom":"TEST"}',$1,${lien})`;
  await db.query(`do $$ begin for i in 1..60 loop insert into public.koki_records(kind,statut,payload,client_id,parent_id,provider_id) values('commandes','Livrée','{"nom":"TEST"}','${testActors.client}',${lien});end loop;end $$`);
  await assert.rejects(db.query(demande,[testActors.client]),/Trop de demandes/);
  await db.query(demande,[testActors.other]); // le quota est par compte
  // Quota quotidien : 300 demandes datant de plus d'une heure.
  await db.query('alter table public.koki_records disable trigger records_stamp'); // sinon created_at est forcé à maintenant : on ne peut pas antidater
  await db.query(`do $$ begin for i in 1..300 loop insert into public.koki_records(kind,statut,payload,client_id,parent_id,provider_id,created_at) values('commandes','Livrée','{"nom":"TEST"}','${testActors.provider}',${lien},now()-interval '2 hours');end loop;end $$`);
  await db.query('alter table public.koki_records enable trigger records_stamp');
  await assert.rejects(db.query(demande,[testActors.provider]),/Limite quotidienne de demandes/);
  // Créations d'un professionnel : on complète jusqu'à 500 fiches dans la journée, la suivante est refusée.
  await db.query(`do $$ declare n integer;begin select count(*) into n from public.koki_records where owner_id='${testActors.merchant}';for i in n+1..500 loop insert into public.koki_records(kind,statut,payload,owner_id,parent_id) values('produits','Disponible','{"nom":"TEST"}','${testActors.merchant}','${f.shop.id}');end loop;end $$`);
  await assert.rejects(db.query(`insert into public.koki_records(kind,statut,payload,owner_id,parent_id) values('produits','Disponible','{"nom":"TEST"}',$1,$2)`,[testActors.merchant,f.shop.id]),/Limite quotidienne de créations/);
 }finally{await pg.close();}
});
test('la proposition est additive : aucune suppression de table, de colonne ni de données',async()=>{
 const sql=await sqlFile();
 assert.doesNotMatch(sql,/\b(drop\s+(table|column|schema|function|index)|truncate|delete\s+from|alter\s+table\s+\S+\s+drop)\b/i);
 assert.match(sql,/drop trigger if exists koki_quota_ecriture/);
});
