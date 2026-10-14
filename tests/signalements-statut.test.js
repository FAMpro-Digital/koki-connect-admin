// Transport · Signalements : traitement par l'administration (proposition signalements-statut.sql).
import test from 'node:test';import assert from 'node:assert/strict';import {randomUUID as key} from 'node:crypto';import fs from 'node:fs';
import {setupBusinessDB,actor,rpc,testActors as A,point,destination,fixtureBusiness} from './helpers/business-db.js';
async function base(){
 if(process.env.KOKI_DB_ADAPTER){const {psqlDB}=await import(process.env.KOKI_DB_ADAPTER);return psqlDB(process.env.KOKI_DB_NAME);}
 const {PGlite}=await import('@electric-sql/pglite');const pg=new PGlite();return {query:(q,v)=>v?pg.query(q,v):pg.exec(q).then(x=>x.at(-1)),close:()=>pg.close()};
}
test('signalement : statut et note par l’administration Transport (MFA), journalisés, sans autre accès',async()=>{
 const db=await base();
 try{
  await setupBusinessDB(db);const f=await fixtureBusiness(db);
  await actor(db,A.client);const q=await rpc(db,'quote',{category:'Taxi',start:point,end:destination});const ride=await rpc(db,'reserve_ride',{request_id:key(),vehicle_id:f.vehicle.id,quote_id:q.quote_id});
  assert.deepEqual(await rpc(db,'report_ride',{id:ride.id,motif:'Prix',details:'Prix différent'}),{ok:true});
  await actor(db,A.admin,'aal2');let [s]=await rpc(db,'admin_ride_reports',{});assert.equal(s.statut,'Nouveau');assert.equal(s.note_admin,null);assert.equal(s.traite_le,null);
  const changer=(extra={})=>rpc(db,'admin_ride_report_status',{request_id:key(),id:s.id,statut:'En cours',...extra});
  // Ni le client, ni un éditeur, ni un administrateur sans double authentification.
  await actor(db,A.client);await assert.rejects(changer(),/Transport et MFA/);await assert.rejects(rpc(db,'admin_ride_reports',{}),/Transport et MFA/);
  await actor(db,A.editor,'aal2');await assert.rejects(changer(),/Transport et MFA/);
  await actor(db,A.admin,'aal1');await assert.rejects(changer(),/Transport et MFA/);
  await actor(db,'');await assert.rejects(changer(),/Transport et MFA/);
  await actor(db,A.admin,'aal2');
  await assert.rejects(changer({statut:'Clos'}),/Statut de signalement invalide/);
  await assert.rejects(changer({statut:'Traité'}),/note obligatoire/);
  await assert.rejects(changer({note:'ok'}),/3 à 500/);
  await assert.rejects(changer({note:'x'.repeat(501)}),/3 à 500/);
  await assert.rejects(changer({note:5}),/Note invalide/);
  await assert.rejects(changer({motif:'Autre'}),/Champs inconnus/);
  await assert.rejects(changer({id:key()}),/introuvable/);
  const enCours=await changer({note:'Client rappelé'});assert.equal(enCours.statut,'En cours');assert.equal(enCours.note_admin,'Client rappelé');
  const traite=await changer({statut:'Traité',note:'  Chauffeur averti, prix remboursé  '});assert.equal(traite.statut,'Traité');assert.equal(traite.note_admin,'Chauffeur averti, prix remboursé');
  [s]=await rpc(db,'admin_ride_reports',{});assert.equal(s.statut,'Traité');assert.equal(s.note_admin,'Chauffeur averti, prix remboursé');assert.ok(s.traite_le);
  // La note est conservée si on rouvre sans en écrire une nouvelle.
  assert.equal((await changer({statut:'Nouveau'})).note_admin,'Chauffeur averti, prix remboursé');
  await db.query('reset role');
  const journal=(await db.query("select details from public.koki_audit where operation='SIGNALEMENT' and record_id=$1 order by id",[s.id])).rows.map(r=>r.details.avant+'→'+r.details.apres);
  assert.deepEqual(journal,['Nouveau→En cours','En cours→Traité','Traité→Nouveau']);
  // Accès direct à la table toujours refusé.
  await actor(db,A.admin,'aal2');await assert.rejects(db.query('select * from koki_private.ride_reports'));
 }finally{await db.close();}
});
test('fichier de production : garde, même contenu que la proposition, retour arrière',()=>{
 const prop=fs.readFileSync(new URL('../supabase/proposals/signalements-statut.sql',import.meta.url),'utf8'),prod=fs.readFileSync(new URL('../supabase/production/signalements-statut.sql',import.meta.url),'utf8');
 assert.ok(prod.endsWith(prop));assert.match(prod,/^-- PRODUCTION : à lancer UNIQUEMENT après autorisation/);
 assert.match(prop,/<>'ed14f4a6970cf05f067629a83b15070c' then raise exception/);assert.match(prop,/-- Retour arrière/);
 assert.doesNotMatch(prop,/create or replace function koki_private\.(transport_plus|commerce_admin)/);
});
